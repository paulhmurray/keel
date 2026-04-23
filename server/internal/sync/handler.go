package sync

import (
	"context"
	"encoding/base64"
	"io"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// dbPool is the subset of pgxpool.Pool used by this handler.
// Using an interface allows the handler to be tested with a mock DB.
type dbPool interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}

type Handler struct {
	db dbPool
}

func NewHandler(db *pgxpool.Pool) *Handler {
	return &Handler{db: db}
}

type projectSummary struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	UpdatedAt time.Time `json:"updated_at"`
}

type createProjectRequest struct {
	ID   string `json:"id" binding:"required"`
	Name string `json:"name" binding:"required"`
}

type updateProjectRequest struct {
	Name string `json:"name" binding:"required"`
}

// ListProjects handles GET /projects — returns id, name, updated_at (not encrypted_data)
func (h *Handler) ListProjects(c *gin.Context) {
	userID := c.GetString("userID")

	rows, err := h.db.Query(c.Request.Context(),
		`SELECT id, name, updated_at FROM projects WHERE user_id = $1 ORDER BY updated_at DESC`,
		userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to query projects"})
		return
	}
	defer rows.Close()

	projects := make([]projectSummary, 0)
	for rows.Next() {
		var p projectSummary
		if err := rows.Scan(&p.ID, &p.Name, &p.UpdatedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to scan project"})
			return
		}
		projects = append(projects, p)
	}

	c.JSON(http.StatusOK, projects)
}

// CreateProject handles POST /projects
func (h *Handler) CreateProject(c *gin.Context) {
	userID := c.GetString("userID")

	var req createProjectRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate the client-supplied ID is a valid UUID
	if _, err := uuid.Parse(req.ID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "id must be a valid UUID"})
		return
	}

	var id string
	var updatedAt time.Time
	err := h.db.QueryRow(c.Request.Context(),
		`INSERT INTO projects (id, user_id, name, updated_at)
		 VALUES ($1, $2, $3, NOW())
		 ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, updated_at = NOW()
		 RETURNING id, updated_at`,
		req.ID, userID, req.Name,
	).Scan(&id, &updatedAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create project"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"id": id, "updated_at": updatedAt})
}

// UpdateProject handles PUT /projects/:id
func (h *Handler) UpdateProject(c *gin.Context) {
	userID := c.GetString("userID")
	projectID := c.Param("id")

	if _, err := uuid.Parse(projectID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid project id"})
		return
	}

	var req updateProjectRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	result, err := h.db.Exec(c.Request.Context(),
		`UPDATE projects SET name = $1, updated_at = NOW()
		 WHERE id = $2 AND user_id = $3`,
		req.Name, projectID, userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update project"})
		return
	}
	if result.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "project not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"id": projectID, "name": req.Name})
}

// DeleteProject handles DELETE /projects/:id
func (h *Handler) DeleteProject(c *gin.Context) {
	userID := c.GetString("userID")
	projectID := c.Param("id")

	if _, err := uuid.Parse(projectID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid project id"})
		return
	}

	result, err := h.db.Exec(c.Request.Context(),
		`DELETE FROM projects WHERE id = $1 AND user_id = $2`,
		projectID, userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete project"})
		return
	}
	if result.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "project not found"})
		return
	}

	c.JSON(http.StatusNoContent, nil)
}

// requireSoloPlan checks the user's plan and aborts with 403 if not solo.
func (h *Handler) requireSoloPlan(c *gin.Context) bool {
	userID := c.GetString("userID")
	var plan string
	err := h.db.QueryRow(c.Request.Context(),
		`SELECT plan FROM users WHERE id = $1`, userID,
	).Scan(&plan)
	if err != nil || plan != "solo" {
		c.JSON(http.StatusForbidden, gin.H{"error": "sync requires a Solo plan"})
		return false
	}
	return true
}

// PushSync handles POST /projects/:id/sync
// Body is raw base64-encoded encrypted bytes (Content-Type: application/octet-stream)
func (h *Handler) PushSync(c *gin.Context) {
	if !h.requireSoloPlan(c) {
		return
	}

	userID := c.GetString("userID")
	projectID := c.Param("id")

	if _, err := uuid.Parse(projectID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid project id"})
		return
	}

	// Check ownership
	var exists bool
	err := h.db.QueryRow(c.Request.Context(),
		`SELECT EXISTS(SELECT 1 FROM projects WHERE id = $1 AND user_id = $2)`,
		projectID, userID,
	).Scan(&exists)
	if err != nil || !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "project not found"})
		return
	}

	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to read body"})
		return
	}

	// Body is base64-encoded; decode to raw bytes for storage
	encrypted, err := base64.StdEncoding.DecodeString(string(body))
	if err != nil {
		// Try URL-safe base64 as a fallback
		encrypted, err = base64.URLEncoding.DecodeString(string(body))
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "body must be base64-encoded"})
			return
		}
	}

	var updatedAt time.Time
	err = h.db.QueryRow(c.Request.Context(),
		`UPDATE projects SET encrypted_data = $1, updated_at = NOW()
		 WHERE id = $2 AND user_id = $3
		 RETURNING updated_at`,
		encrypted, projectID, userID,
	).Scan(&updatedAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to store sync data"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"updated_at": updatedAt})
}

// PullSync handles GET /projects/:id/sync
// Returns base64-encoded encrypted_data
func (h *Handler) PullSync(c *gin.Context) {
	if !h.requireSoloPlan(c) {
		return
	}

	userID := c.GetString("userID")
	projectID := c.Param("id")

	if _, err := uuid.Parse(projectID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid project id"})
		return
	}

	var encryptedData []byte
	var updatedAt time.Time
	err := h.db.QueryRow(c.Request.Context(),
		`SELECT encrypted_data, updated_at FROM projects WHERE id = $1 AND user_id = $2`,
		projectID, userID,
	).Scan(&encryptedData, &updatedAt)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "project not found"})
		return
	}

	if encryptedData == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "no sync data available"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"encrypted_data": base64.StdEncoding.EncodeToString(encryptedData),
		"updated_at":     updatedAt,
	})
}
