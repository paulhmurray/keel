package inbox

import (
	"encoding/base64"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Handler holds the database pool for inbox operations.
type Handler struct {
	db *pgxpool.Pool
}

// NewHandler creates a new inbox Handler.
func NewHandler(db *pgxpool.Pool) *Handler {
	return &Handler{db: db}
}

// createRequest is the body for POST /inbox.
type createRequest struct {
	Source    string  `json:"source"`
	Content   string  `json:"content" binding:"required"`
	ImageData *string `json:"image_data"` // base64-encoded, nullable
	Caption   *string `json:"caption"`
	ProjectID *string `json:"project_id"`
}

// createResponse is returned from POST /inbox.
type createResponse struct {
	ID        string    `json:"id"`
	CreatedAt time.Time `json:"created_at"`
}

// listItem is a single element returned from GET /inbox.
type listItem struct {
	ID        string    `json:"id"`
	Source    string    `json:"source"`
	Content   string    `json:"content"`
	Caption   *string   `json:"caption"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

// updateStatusRequest is the body for PATCH /inbox/:id.
type updateStatusRequest struct {
	Status string `json:"status" binding:"required"`
}

// Create handles POST /inbox — inserts a new inbox item for the authenticated user.
func (h *Handler) Create(c *gin.Context) {
	userID, _ := c.Get("userID")

	var req createRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Default source
	source := req.Source
	if source == "" {
		source = "mobile_note"
	}

	// Decode base64 image data if provided
	var imageBytes []byte
	if req.ImageData != nil && *req.ImageData != "" {
		decoded, err := base64.StdEncoding.DecodeString(*req.ImageData)
		if err != nil {
			// Try URL-safe base64
			decoded, err = base64.URLEncoding.DecodeString(*req.ImageData)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid base64 image_data"})
				return
			}
		}
		imageBytes = decoded
	}

	var id string
	var createdAt time.Time

	err := h.db.QueryRow(c.Request.Context(),
		`INSERT INTO inbox_items (user_id, project_id, source, content, image_data, caption)
		 VALUES ($1, $2, $3, $4, $5, $6)
		 RETURNING id, created_at`,
		userID, req.ProjectID, source, req.Content, imageBytes, req.Caption,
	).Scan(&id, &createdAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create inbox item"})
		return
	}

	c.JSON(http.StatusCreated, createResponse{
		ID:        id,
		CreatedAt: createdAt,
	})
}

// List handles GET /inbox — returns pending (or filtered) items for the authenticated user.
// Does not include image_data (too large for list responses).
func (h *Handler) List(c *gin.Context) {
	userID, _ := c.Get("userID")

	status := c.DefaultQuery("status", "pending")

	rows, err := h.db.Query(c.Request.Context(),
		`SELECT id, source, content, caption, status, created_at
		 FROM inbox_items
		 WHERE user_id = $1 AND status = $2
		 ORDER BY created_at DESC`,
		userID, status,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to query inbox"})
		return
	}
	defer rows.Close()

	items := make([]listItem, 0)
	for rows.Next() {
		var item listItem
		if err := rows.Scan(&item.ID, &item.Source, &item.Content, &item.Caption, &item.Status, &item.CreatedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to scan inbox item"})
			return
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to iterate inbox items"})
		return
	}

	c.JSON(http.StatusOK, items)
}

// GetImage handles GET /inbox/:id/image — returns raw image bytes for an item.
func (h *Handler) GetImage(c *gin.Context) {
	userID, _ := c.Get("userID")
	itemID := c.Param("id")

	var imageData []byte
	err := h.db.QueryRow(c.Request.Context(),
		`SELECT image_data FROM inbox_items WHERE id = $1 AND user_id = $2`,
		itemID, userID,
	).Scan(&imageData)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "item not found"})
		return
	}

	if len(imageData) == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "no image for this item"})
		return
	}

	c.Data(http.StatusOK, "image/jpeg", imageData)
}

// UpdateStatus handles PATCH /inbox/:id — updates the status of an inbox item.
func (h *Handler) UpdateStatus(c *gin.Context) {
	userID, _ := c.Get("userID")
	itemID := c.Param("id")

	var req updateStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Status != "accepted" && req.Status != "rejected" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "status must be 'accepted' or 'rejected'"})
		return
	}

	tag, err := h.db.Exec(c.Request.Context(),
		`UPDATE inbox_items SET status = $1 WHERE id = $2 AND user_id = $3`,
		req.Status, itemID, userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update status"})
		return
	}

	if tag.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "item not found or not owned by user"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": req.Status})
}
