// Package links implements the programme ↔ project link endpoints
// (Phase B) plus the cascade payload routing on top (Phase C). The
// link contract: two parties exchange a shared code off-band, each
// calls PUT /links/:code/me to claim their side, and when both sides
// are present the link activates. The cascade contract: either party
// can PUT items keyed by (kind, item_id) to /links/:code/items, and
// either party can GET the channel to reconcile their local view.
package links

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// dbPool mirrors the interface used by the sync handler so this
// handler is testable with a stub.
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

// NewHandlerWithDB lets tests inject a mock dbPool.
func NewHandlerWithDB(db dbPool) *Handler {
	return &Handler{db: db}
}

type claimRequest struct {
	EntityID string `json:"entity_id" binding:"required"`
	Kind     string `json:"kind" binding:"required,oneof=project programme"`
	Name     string `json:"name" binding:"required"`
}

type sideResponse struct {
	UserID   string `json:"user_id,omitempty"`
	EntityID string `json:"entity_id,omitempty"`
	Kind     string `json:"kind,omitempty"`
	Name     string `json:"name,omitempty"`
}

type linkResponse struct {
	Code        string        `json:"code"`
	SideA       sideResponse  `json:"side_a"`
	SideB       *sideResponse `json:"side_b,omitempty"`
	ActivatedAt *time.Time    `json:"activated_at,omitempty"`
	CreatedAt   time.Time     `json:"created_at"`
}

// linkRow mirrors the programme_links table.
type linkRow struct {
	Code           string
	SideAUserID    string
	SideAEntityID  string
	SideAKind      string
	SideAName      string
	SideBUserID    sql.NullString
	SideBEntityID  sql.NullString
	SideBKind      sql.NullString
	SideBName      sql.NullString
	CreatedAt      time.Time
	ActivatedAt    sql.NullTime
}

func (r *linkRow) toResponse() linkResponse {
	resp := linkResponse{
		Code: r.Code,
		SideA: sideResponse{
			UserID:   r.SideAUserID,
			EntityID: r.SideAEntityID,
			Kind:     r.SideAKind,
			Name:     r.SideAName,
		},
		CreatedAt: r.CreatedAt,
	}
	if r.SideBUserID.Valid {
		resp.SideB = &sideResponse{
			UserID:   r.SideBUserID.String,
			EntityID: r.SideBEntityID.String,
			Kind:     r.SideBKind.String,
			Name:     r.SideBName.String,
		}
	}
	if r.ActivatedAt.Valid {
		t := r.ActivatedAt.Time
		resp.ActivatedAt = &t
	}
	return resp
}

func (h *Handler) loadLink(ctx context.Context, code string) (*linkRow, error) {
	r := h.db.QueryRow(ctx, `
		SELECT code,
		       side_a_user_id, side_a_entity_id, side_a_kind, side_a_name,
		       side_b_user_id, side_b_entity_id, side_b_kind, side_b_name,
		       created_at, activated_at
		FROM programme_links
		WHERE code = $1
	`, code)
	row := &linkRow{}
	err := r.Scan(
		&row.Code,
		&row.SideAUserID, &row.SideAEntityID, &row.SideAKind, &row.SideAName,
		&row.SideBUserID, &row.SideBEntityID, &row.SideBKind, &row.SideBName,
		&row.CreatedAt, &row.ActivatedAt,
	)
	if err != nil {
		return nil, err
	}
	return row, nil
}

// ClaimSide handles PUT /links/:code/me — the user claims their side
// of the link. Logic:
//   - If the code is unknown: insert a row with this user as side A.
//   - If the code is known with side A only:
//       - If side A is this user: idempotent — overwrite the side A
//         identity (allows a re-link after deleting and recreating an
//         entity client-side).
//       - Otherwise: populate side B with this user and stamp
//         activated_at.
//   - If the code is known with both sides claimed:
//       - If this user is side A: overwrite side A identity (re-link).
//       - If this user is side B: overwrite side B identity.
//       - Otherwise: 409 — the link slots are taken.
func (h *Handler) ClaimSide(c *gin.Context) {
	userID := c.GetString("userID")
	code := c.Param("code")
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "code is required"})
		return
	}

	var req claimRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	existing, err := h.loadLink(c.Request.Context(), code)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load link"})
		return
	}

	if existing == nil {
		// First claimant becomes side A.
		_, err := h.db.Exec(c.Request.Context(), `
			INSERT INTO programme_links
			    (code, side_a_user_id, side_a_entity_id, side_a_kind, side_a_name)
			VALUES ($1, $2, $3, $4, $5)
		`, code, userID, req.EntityID, req.Kind, req.Name)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create link"})
			return
		}
		reloaded, _ := h.loadLink(c.Request.Context(), code)
		c.JSON(http.StatusOK, reloaded.toResponse())
		return
	}

	// Existing row — figure out which side this user owns (if any).
	isSideA := existing.SideAUserID == userID
	isSideB := existing.SideBUserID.Valid && existing.SideBUserID.String == userID

	if isSideA {
		// Re-claim side A — update identity, leave the rest alone.
		_, err := h.db.Exec(c.Request.Context(), `
			UPDATE programme_links
			SET side_a_entity_id = $2, side_a_kind = $3, side_a_name = $4
			WHERE code = $1
		`, code, req.EntityID, req.Kind, req.Name)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update side"})
			return
		}
		reloaded, _ := h.loadLink(c.Request.Context(), code)
		c.JSON(http.StatusOK, reloaded.toResponse())
		return
	}

	if isSideB {
		_, err := h.db.Exec(c.Request.Context(), `
			UPDATE programme_links
			SET side_b_entity_id = $2, side_b_kind = $3, side_b_name = $4
			WHERE code = $1
		`, code, req.EntityID, req.Kind, req.Name)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update side"})
			return
		}
		reloaded, _ := h.loadLink(c.Request.Context(), code)
		c.JSON(http.StatusOK, reloaded.toResponse())
		return
	}

	// Different user — claim side B if it's empty.
	if existing.SideBUserID.Valid {
		c.JSON(http.StatusConflict,
			gin.H{"error": "link already has two parties"})
		return
	}

	// Don't allow linking two entities of the same kind. A project
	// links to a programme (or vice versa), never project↔project.
	if existing.SideAKind == req.Kind {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "link sides must be one project + one programme",
		})
		return
	}

	_, err = h.db.Exec(c.Request.Context(), `
		UPDATE programme_links
		SET side_b_user_id = $2,
		    side_b_entity_id = $3,
		    side_b_kind = $4,
		    side_b_name = $5,
		    activated_at = NOW()
		WHERE code = $1
	`, code, userID, req.EntityID, req.Kind, req.Name)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to claim side"})
		return
	}
	reloaded, _ := h.loadLink(c.Request.Context(), code)
	c.JSON(http.StatusOK, reloaded.toResponse())
}

// GetLink handles GET /links/:code — reads the link state. Only
// parties to the link can read it; everyone else sees 404 (to avoid
// leaking which codes exist).
func (h *Handler) GetLink(c *gin.Context) {
	userID := c.GetString("userID")
	code := c.Param("code")
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "code is required"})
		return
	}

	row, err := h.loadLink(c.Request.Context(), code)
	if errors.Is(err, pgx.ErrNoRows) || row == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "link not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load link"})
		return
	}

	isSideA := row.SideAUserID == userID
	isSideB := row.SideBUserID.Valid && row.SideBUserID.String == userID
	if !isSideA && !isSideB {
		c.JSON(http.StatusNotFound, gin.H{"error": "link not found"})
		return
	}

	c.JSON(http.StatusOK, row.toResponse())
}

// RevokeSide handles DELETE /links/:code/me — the user removes their
// side. If they're the only side present, the whole row is deleted
// (the link never activated). If both sides are present, the row is
// downgraded to the other side only and activated_at is cleared.
func (h *Handler) RevokeSide(c *gin.Context) {
	userID := c.GetString("userID")
	code := c.Param("code")
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "code is required"})
		return
	}

	row, err := h.loadLink(c.Request.Context(), code)
	if errors.Is(err, pgx.ErrNoRows) || row == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "link not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load link"})
		return
	}

	isSideA := row.SideAUserID == userID
	isSideB := row.SideBUserID.Valid && row.SideBUserID.String == userID
	if !isSideA && !isSideB {
		c.JSON(http.StatusNotFound, gin.H{"error": "link not found"})
		return
	}

	if !row.SideBUserID.Valid {
		// Only side A exists and it's us — delete the row.
		_, err := h.db.Exec(c.Request.Context(),
			`DELETE FROM programme_links WHERE code = $1`, code)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete link"})
			return
		}
		c.Status(http.StatusNoContent)
		return
	}

	if isSideA {
		// Promote side B to side A so the row stays valid (NOT NULL
		// constraints on side A); clear side B; clear activation.
		_, err := h.db.Exec(c.Request.Context(), `
			UPDATE programme_links
			SET side_a_user_id   = side_b_user_id,
			    side_a_entity_id = side_b_entity_id,
			    side_a_kind      = side_b_kind,
			    side_a_name      = side_b_name,
			    side_b_user_id   = NULL,
			    side_b_entity_id = NULL,
			    side_b_kind      = NULL,
			    side_b_name      = NULL,
			    activated_at     = NULL
			WHERE code = $1
		`, code)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to revoke side"})
			return
		}
	} else {
		// isSideB — just blank out side B.
		_, err := h.db.Exec(c.Request.Context(), `
			UPDATE programme_links
			SET side_b_user_id   = NULL,
			    side_b_entity_id = NULL,
			    side_b_kind      = NULL,
			    side_b_name      = NULL,
			    activated_at     = NULL
			WHERE code = $1
		`, code)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to revoke side"})
			return
		}
	}
	c.Status(http.StatusNoContent)
}

// ── Cascade items (Phase C) ────────────────────────────────────────────

type cascadeRequest struct {
	SourceEntityID string          `json:"source_entity_id" binding:"required"`
	ItemKind       string          `json:"item_kind" binding:"required"`
	ItemID         string          `json:"item_id" binding:"required"`
	Payload        json.RawMessage `json:"payload" binding:"required"`
}

type cascadedItem struct {
	SourceEntityID string          `json:"source_entity_id"`
	ItemKind       string          `json:"item_kind"`
	ItemID         string          `json:"item_id"`
	Payload        json.RawMessage `json:"payload"`
	UpdatedAt      time.Time       `json:"updated_at"`
	Deleted        bool            `json:"deleted,omitempty"`
}

type cascadeListResponse struct {
	Items  []cascadedItem `json:"items"`
	Cursor string         `json:"cursor"`
}

// assertLinkParty confirms the caller is one of the two parties on
// the link. Mirrors the 404-for-non-parties pattern in GetLink so
// codes can't be enumerated by probing /items.
func (h *Handler) assertLinkParty(c *gin.Context, code, userID string) (*linkRow, bool) {
	row, err := h.loadLink(c.Request.Context(), code)
	if errors.Is(err, pgx.ErrNoRows) || row == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "link not found"})
		return nil, false
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load link"})
		return nil, false
	}
	isSideA := row.SideAUserID == userID
	isSideB := row.SideBUserID.Valid && row.SideBUserID.String == userID
	if !isSideA && !isSideB {
		c.JSON(http.StatusNotFound, gin.H{"error": "link not found"})
		return nil, false
	}
	return row, true
}

// PushCascadeItem handles PUT /links/:code/items — upsert keyed by
// (kind, item_id). Only link parties can push; payload shape is
// the receiving client's responsibility to validate.
func (h *Handler) PushCascadeItem(c *gin.Context) {
	userID := c.GetString("userID")
	code := c.Param("code")

	if _, ok := h.assertLinkParty(c, code, userID); !ok {
		return
	}

	var req cascadeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err := h.db.Exec(c.Request.Context(), `
		INSERT INTO cascaded_items
		    (code, source_user_id, source_entity_id, item_kind, item_id, payload, updated_at, deleted_at)
		VALUES ($1, $2, $3, $4, $5, $6, NOW(), NULL)
		ON CONFLICT (code, item_kind, item_id) DO UPDATE
		SET payload          = EXCLUDED.payload,
		    updated_at       = NOW(),
		    deleted_at       = NULL,
		    source_user_id   = EXCLUDED.source_user_id,
		    source_entity_id = EXCLUDED.source_entity_id
	`, code, userID, req.SourceEntityID, req.ItemKind, req.ItemID, []byte(req.Payload))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to upsert cascade item"})
		return
	}
	c.Status(http.StatusNoContent)
}

// PullCascadeItems handles GET /links/:code/items[?since=...] — lists
// items changed after the cursor (or everything if no cursor). The
// response cursor is the max updated_at across returned rows; callers
// pass it back on the next pull for an incremental delta.
func (h *Handler) PullCascadeItems(c *gin.Context) {
	userID := c.GetString("userID")
	code := c.Param("code")

	if _, ok := h.assertLinkParty(c, code, userID); !ok {
		return
	}

	var since *time.Time
	if raw := c.Query("since"); raw != "" {
		t, err := time.Parse(time.RFC3339Nano, raw)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "since must be RFC3339"})
			return
		}
		since = &t
	}

	var (
		rows pgx.Rows
		err  error
	)
	if since != nil {
		rows, err = h.db.Query(c.Request.Context(), `
			SELECT source_entity_id, item_kind, item_id, payload, updated_at, deleted_at
			FROM cascaded_items
			WHERE code = $1 AND updated_at > $2
			ORDER BY updated_at ASC
		`, code, *since)
	} else {
		rows, err = h.db.Query(c.Request.Context(), `
			SELECT source_entity_id, item_kind, item_id, payload, updated_at, deleted_at
			FROM cascaded_items
			WHERE code = $1
			ORDER BY updated_at ASC
		`, code)
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list cascade items"})
		return
	}
	defer rows.Close()

	items := make([]cascadedItem, 0)
	var maxUpdated time.Time
	for rows.Next() {
		var (
			it        cascadedItem
			payload   []byte
			deletedAt sql.NullTime
		)
		if err := rows.Scan(&it.SourceEntityID, &it.ItemKind, &it.ItemID,
			&payload, &it.UpdatedAt, &deletedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to scan cascade item"})
			return
		}
		it.Payload = json.RawMessage(payload)
		it.Deleted = deletedAt.Valid
		items = append(items, it)
		if it.UpdatedAt.After(maxUpdated) {
			maxUpdated = it.UpdatedAt
		}
	}

	resp := cascadeListResponse{Items: items}
	if !maxUpdated.IsZero() {
		resp.Cursor = maxUpdated.UTC().Format(time.RFC3339Nano)
	} else if since != nil {
		resp.Cursor = since.UTC().Format(time.RFC3339Nano)
	}
	c.JSON(http.StatusOK, resp)
}

// DeleteCascadeItem handles DELETE /links/:code/items/:kind/:id —
// soft-tombstones the row so other parties see the delete on their
// next pull.
func (h *Handler) DeleteCascadeItem(c *gin.Context) {
	userID := c.GetString("userID")
	code := c.Param("code")
	kind := c.Param("kind")
	id := c.Param("id")

	if _, ok := h.assertLinkParty(c, code, userID); !ok {
		return
	}

	tag, err := h.db.Exec(c.Request.Context(), `
		UPDATE cascaded_items
		SET deleted_at = NOW(), updated_at = NOW()
		WHERE code = $1 AND item_kind = $2 AND item_id = $3
	`, code, kind, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete cascade item"})
		return
	}
	if tag.RowsAffected() == 0 {
		c.Status(http.StatusNotFound)
		return
	}
	c.Status(http.StatusNoContent)
}
