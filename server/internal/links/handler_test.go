package links

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

func init() {
	gin.SetMode(gin.TestMode)
}

// ---------------------------------------------------------------------------
// Mock DB helpers
// ---------------------------------------------------------------------------

type mockDB struct {
	rows           map[string]*linkRow            // keyed by code
	cascadeStorage []mockCascadedRow              // sequential append-only log
}

// mockCascadedRow models one cascaded_items row for tests. Fields
// mirror the Postgres columns we care about — including deleted_at so
// pull queries can filter / surface tombstones.
type mockCascadedRow struct {
	code           string
	sourceUserID   string
	sourceEntityID string
	itemKind       string
	itemID         string
	payload        []byte
	updatedAt      time.Time
	deletedAt      sql.NullTime
}

func (m *mockDB) QueryRow(ctx context.Context, sql string, args ...any) pgx.Row {
	// Only one QueryRow shape used: load by code.
	code := args[0].(string)
	row, ok := m.rows[code]
	if !ok {
		return &mockRow{err: pgx.ErrNoRows}
	}
	values := []any{
		row.Code,
		row.SideAUserID, row.SideAEntityID, row.SideAKind, row.SideAName,
		row.SideBUserID, row.SideBEntityID, row.SideBKind, row.SideBName,
		row.CreatedAt, row.ActivatedAt,
	}
	return &mockRow{values: values}
}

func (m *mockDB) Query(ctx context.Context, sqlStmt string, args ...any) (pgx.Rows, error) {
	// Cascade pull queries — filter the in-memory log by code (+ since
	// when supplied) and return a mockRows the handler can drain.
	if strings.Contains(sqlStmt, "FROM cascaded_items") {
		code := args[0].(string)
		var since *time.Time
		if len(args) > 1 {
			t := args[1].(time.Time)
			since = &t
		}
		out := make([][]any, 0)
		for _, r := range m.cascadeStorage {
			if r.code != code {
				continue
			}
			if since != nil && !r.updatedAt.After(*since) {
				continue
			}
			out = append(out, []any{
				r.sourceEntityID,
				r.itemKind,
				r.itemID,
				r.payload,
				r.updatedAt,
				r.deletedAt,
			})
		}
		return &mockRows{data: out}, nil
	}
	return nil, errors.New("unexpected Query: " + sqlStmt[:min(80, len(sqlStmt))])
}

// mockRows reuses the lightweight pattern from the sync handler tests.
type mockRows struct {
	data [][]any
	pos  int
}

func (r *mockRows) Next() bool                                   { r.pos++; return r.pos <= len(r.data) }
func (r *mockRows) Close()                                       {}
func (r *mockRows) Err() error                                   { return nil }
func (r *mockRows) CommandTag() pgconn.CommandTag                { return pgconn.NewCommandTag("") }
func (r *mockRows) FieldDescriptions() []pgconn.FieldDescription { return nil }
func (r *mockRows) Values() ([]any, error)                       { return nil, nil }
func (r *mockRows) RawValues() [][]byte                          { return nil }
func (r *mockRows) Conn() *pgx.Conn                              { return nil }
func (r *mockRows) Scan(dest ...any) error {
	row := r.data[r.pos-1]
	for i, d := range dest {
		if i >= len(row) {
			break
		}
		reflect.ValueOf(d).Elem().Set(reflect.ValueOf(row[i]))
	}
	return nil
}

func (m *mockDB) Exec(ctx context.Context, sqlStmt string, args ...any) (pgconn.CommandTag, error) {
	// Branch on a quick fingerprint so the mock can simulate inserts /
	// updates / deletes without parsing the actual SQL.
	switch {
	case strings.Contains(sqlStmt, "INSERT INTO programme_links"):
		// args: code, side_a_user_id, entity_id, kind, name
		code := args[0].(string)
		m.rows[code] = &linkRow{
			Code:          code,
			SideAUserID:   args[1].(string),
			SideAEntityID: args[2].(string),
			SideAKind:     args[3].(string),
			SideAName:     args[4].(string),
			CreatedAt:     time.Now().UTC(),
		}
	case strings.Contains(sqlStmt, "SET side_a_entity_id"):
		// Re-claim side A.
		code := args[0].(string)
		r := m.rows[code]
		r.SideAEntityID = args[1].(string)
		r.SideAKind = args[2].(string)
		r.SideAName = args[3].(string)
	case strings.Contains(sqlStmt, "SET side_b_entity_id = $2, side_b_kind = $3, side_b_name = $4"):
		// Re-claim side B.
		code := args[0].(string)
		r := m.rows[code]
		r.SideBEntityID = sql.NullString{String: args[1].(string), Valid: true}
		r.SideBKind = sql.NullString{String: args[2].(string), Valid: true}
		r.SideBName = sql.NullString{String: args[3].(string), Valid: true}
	case strings.Contains(sqlStmt, "SET side_b_user_id = $2"):
		// First claim of side B — activates.
		code := args[0].(string)
		r := m.rows[code]
		r.SideBUserID = sql.NullString{String: args[1].(string), Valid: true}
		r.SideBEntityID = sql.NullString{String: args[2].(string), Valid: true}
		r.SideBKind = sql.NullString{String: args[3].(string), Valid: true}
		r.SideBName = sql.NullString{String: args[4].(string), Valid: true}
		r.ActivatedAt = sql.NullTime{Time: time.Now().UTC(), Valid: true}
	case strings.Contains(sqlStmt, "DELETE FROM programme_links"):
		code := args[0].(string)
		delete(m.rows, code)
	case strings.Contains(sqlStmt, "SET side_a_user_id   = side_b_user_id"):
		// Revoke side A → promote side B to side A.
		code := args[0].(string)
		r := m.rows[code]
		r.SideAUserID = r.SideBUserID.String
		r.SideAEntityID = r.SideBEntityID.String
		r.SideAKind = r.SideBKind.String
		r.SideAName = r.SideBName.String
		r.SideBUserID = sql.NullString{}
		r.SideBEntityID = sql.NullString{}
		r.SideBKind = sql.NullString{}
		r.SideBName = sql.NullString{}
		r.ActivatedAt = sql.NullTime{}
	case strings.Contains(sqlStmt, "SET side_b_user_id   = NULL"):
		// Revoke side B.
		code := args[0].(string)
		r := m.rows[code]
		r.SideBUserID = sql.NullString{}
		r.SideBEntityID = sql.NullString{}
		r.SideBKind = sql.NullString{}
		r.SideBName = sql.NullString{}
		r.ActivatedAt = sql.NullTime{}
	case strings.Contains(sqlStmt, "INSERT INTO cascaded_items"):
		// args: code, source_user_id, source_entity_id, item_kind, item_id, payload
		code := args[0].(string)
		kind := args[3].(string)
		id := args[4].(string)
		now := time.Now().UTC()
		// Upsert: replace existing row with same (code, kind, id).
		for i, r := range m.cascadeStorage {
			if r.code == code && r.itemKind == kind && r.itemID == id {
				m.cascadeStorage[i] = mockCascadedRow{
					code:           code,
					sourceUserID:   args[1].(string),
					sourceEntityID: args[2].(string),
					itemKind:       kind,
					itemID:         id,
					payload:        args[5].([]byte),
					updatedAt:      now,
				}
				return pgconn.NewCommandTag(""), nil
			}
		}
		m.cascadeStorage = append(m.cascadeStorage, mockCascadedRow{
			code:           code,
			sourceUserID:   args[1].(string),
			sourceEntityID: args[2].(string),
			itemKind:       kind,
			itemID:         id,
			payload:        args[5].([]byte),
			updatedAt:      now,
		})
	case strings.Contains(sqlStmt, "UPDATE cascaded_items"):
		code := args[0].(string)
		kind := args[1].(string)
		id := args[2].(string)
		var affected bool
		for i, r := range m.cascadeStorage {
			if r.code == code && r.itemKind == kind && r.itemID == id {
				m.cascadeStorage[i].deletedAt =
					sql.NullTime{Time: time.Now().UTC(), Valid: true}
				m.cascadeStorage[i].updatedAt = time.Now().UTC()
				affected = true
				break
			}
		}
		// pgx's CommandTag string format is "UPDATE n". Building one
		// manually so the handler's RowsAffected() check sees 1 or 0.
		if affected {
			return pgconn.NewCommandTag("UPDATE 1"), nil
		}
		return pgconn.NewCommandTag("UPDATE 0"), nil
	default:
		return pgconn.NewCommandTag(""), errors.New("unexpected Exec: " + sqlStmt[:min(80, len(sqlStmt))])
	}
	return pgconn.NewCommandTag(""), nil
}

// mockRow implements pgx.Row
type mockRow struct {
	values []any
	err    error
}

func (r *mockRow) Scan(dest ...any) error {
	if r.err != nil {
		return r.err
	}
	for i, d := range dest {
		if i >= len(r.values) {
			break
		}
		reflect.ValueOf(d).Elem().Set(reflect.ValueOf(r.values[i]))
	}
	return nil
}

// ---------------------------------------------------------------------------
// Router + request helpers — modelled on the sync handler tests so the
// auth middleware is faked out the same way.
// ---------------------------------------------------------------------------

const (
	userA = "user-a-00000000-0000-0000-0000-000000000001"
	userB = "user-b-00000000-0000-0000-0000-000000000002"
	userC = "user-c-00000000-0000-0000-0000-000000000003"
)

func newRouter(h *Handler, asUser string) *gin.Engine {
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("userID", asUser)
		c.Next()
	})
	r.PUT("/links/:code/me", h.ClaimSide)
	r.GET("/links/:code", h.GetLink)
	r.DELETE("/links/:code/me", h.RevokeSide)
	r.PUT("/links/:code/items", h.PushCascadeItem)
	r.GET("/links/:code/items", h.PullCascadeItems)
	r.DELETE("/links/:code/items/:kind/:id", h.DeleteCascadeItem)
	return r
}

func doRequest(r *gin.Engine, method, path string, body any) *httptest.ResponseRecorder {
	var buf bytes.Buffer
	if body != nil {
		json.NewEncoder(&buf).Encode(body)
	}
	req := httptest.NewRequest(method, path, &buf)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

// ---------------------------------------------------------------------------
// ClaimSide
// ---------------------------------------------------------------------------

func TestClaim_FirstClaimCreatesSideA(t *testing.T) {
	db := &mockDB{rows: map[string]*linkRow{}}
	h := NewHandlerWithDB(db)
	body := map[string]string{"entity_id": "prog-1", "kind": "programme", "name": "Big Prog"}

	w := doRequest(newRouter(h, userA), http.MethodPut, "/links/KL-AAAA/me", body)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var resp linkResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.SideA.UserID != userA || resp.SideA.Kind != "programme" {
		t.Errorf("side A mismatch: %+v", resp.SideA)
	}
	if resp.SideB != nil {
		t.Errorf("side B should be nil, got %+v", resp.SideB)
	}
}

func TestClaim_SecondClaimActivatesLink(t *testing.T) {
	db := &mockDB{rows: map[string]*linkRow{}}
	h := NewHandlerWithDB(db)

	// User A claims first (programme).
	doRequest(newRouter(h, userA), http.MethodPut, "/links/KL-XX/me",
		map[string]string{"entity_id": "prog-1", "kind": "programme", "name": "P"})
	// User B claims second (project, complementary kind).
	w := doRequest(newRouter(h, userB), http.MethodPut, "/links/KL-XX/me",
		map[string]string{"entity_id": "proj-1", "kind": "project", "name": "Q"})
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var resp linkResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.SideB == nil || resp.SideB.UserID != userB || resp.SideB.Kind != "project" {
		t.Errorf("side B mismatch: %+v", resp.SideB)
	}
	if resp.ActivatedAt == nil {
		t.Errorf("activated_at should be set after both sides claim")
	}
}

func TestClaim_SameUserReclaimsSideA(t *testing.T) {
	db := &mockDB{rows: map[string]*linkRow{}}
	h := NewHandlerWithDB(db)

	doRequest(newRouter(h, userA), http.MethodPut, "/links/KL-YY/me",
		map[string]string{"entity_id": "prog-1", "kind": "programme", "name": "P"})
	// Same user updates the entity name.
	w := doRequest(newRouter(h, userA), http.MethodPut, "/links/KL-YY/me",
		map[string]string{"entity_id": "prog-1", "kind": "programme", "name": "Renamed"})
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var resp linkResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.SideA.Name != "Renamed" {
		t.Errorf("expected renamed side A, got %s", resp.SideA.Name)
	}
}

func TestClaim_ThirdPartyConflict(t *testing.T) {
	db := &mockDB{rows: map[string]*linkRow{}}
	h := NewHandlerWithDB(db)

	doRequest(newRouter(h, userA), http.MethodPut, "/links/KL-ZZ/me",
		map[string]string{"entity_id": "prog-1", "kind": "programme", "name": "P"})
	doRequest(newRouter(h, userB), http.MethodPut, "/links/KL-ZZ/me",
		map[string]string{"entity_id": "proj-1", "kind": "project", "name": "Q"})
	// User C tries to muscle in.
	w := doRequest(newRouter(h, userC), http.MethodPut, "/links/KL-ZZ/me",
		map[string]string{"entity_id": "proj-2", "kind": "project", "name": "R"})
	if w.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", w.Code)
	}
}

func TestClaim_RejectsSameKindOnSideB(t *testing.T) {
	db := &mockDB{rows: map[string]*linkRow{}}
	h := NewHandlerWithDB(db)

	doRequest(newRouter(h, userA), http.MethodPut, "/links/KL-K/me",
		map[string]string{"entity_id": "prog-1", "kind": "programme", "name": "P"})
	// User B also tries programme — illegal.
	w := doRequest(newRouter(h, userB), http.MethodPut, "/links/KL-K/me",
		map[string]string{"entity_id": "prog-2", "kind": "programme", "name": "Q"})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
}

func TestClaim_RejectsInvalidKind(t *testing.T) {
	db := &mockDB{rows: map[string]*linkRow{}}
	h := NewHandlerWithDB(db)
	w := doRequest(newRouter(h, userA), http.MethodPut, "/links/KL-Q/me",
		map[string]string{"entity_id": "p", "kind": "team", "name": "X"})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

// ---------------------------------------------------------------------------
// GetLink
// ---------------------------------------------------------------------------

func TestGet_PartyCanRead(t *testing.T) {
	db := &mockDB{rows: map[string]*linkRow{}}
	h := NewHandlerWithDB(db)
	doRequest(newRouter(h, userA), http.MethodPut, "/links/KL-G/me",
		map[string]string{"entity_id": "prog-1", "kind": "programme", "name": "P"})

	w := doRequest(newRouter(h, userA), http.MethodGet, "/links/KL-G", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
}

func TestGet_NonPartyGets404(t *testing.T) {
	db := &mockDB{rows: map[string]*linkRow{}}
	h := NewHandlerWithDB(db)
	doRequest(newRouter(h, userA), http.MethodPut, "/links/KL-H/me",
		map[string]string{"entity_id": "prog-1", "kind": "programme", "name": "P"})
	// Different user reads — should not leak the existence of the code.
	w := doRequest(newRouter(h, userC), http.MethodGet, "/links/KL-H", nil)
	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}

func TestGet_MissingCode(t *testing.T) {
	db := &mockDB{rows: map[string]*linkRow{}}
	h := NewHandlerWithDB(db)
	w := doRequest(newRouter(h, userA), http.MethodGet, "/links/KL-MISSING", nil)
	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}

// ---------------------------------------------------------------------------
// RevokeSide
// ---------------------------------------------------------------------------

func TestRevoke_OnlySideDeletesRow(t *testing.T) {
	db := &mockDB{rows: map[string]*linkRow{}}
	h := NewHandlerWithDB(db)
	doRequest(newRouter(h, userA), http.MethodPut, "/links/KL-R/me",
		map[string]string{"entity_id": "prog-1", "kind": "programme", "name": "P"})
	w := doRequest(newRouter(h, userA), http.MethodDelete, "/links/KL-R/me", nil)
	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", w.Code)
	}
	if _, ok := db.rows["KL-R"]; ok {
		t.Errorf("row should be deleted")
	}
}

func TestRevoke_SideAPromotesSideB(t *testing.T) {
	db := &mockDB{rows: map[string]*linkRow{}}
	h := NewHandlerWithDB(db)
	doRequest(newRouter(h, userA), http.MethodPut, "/links/KL-S/me",
		map[string]string{"entity_id": "prog-1", "kind": "programme", "name": "P"})
	doRequest(newRouter(h, userB), http.MethodPut, "/links/KL-S/me",
		map[string]string{"entity_id": "proj-1", "kind": "project", "name": "Q"})

	// User A (side A) revokes — side B should be promoted.
	w := doRequest(newRouter(h, userA), http.MethodDelete, "/links/KL-S/me", nil)
	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", w.Code)
	}
	row := db.rows["KL-S"]
	if row == nil {
		t.Fatal("row should still exist")
	}
	if row.SideAUserID != userB || row.SideAKind != "project" {
		t.Errorf("expected side B promoted to A, got %+v", row)
	}
	if row.SideBUserID.Valid {
		t.Errorf("side B should be cleared")
	}
	if row.ActivatedAt.Valid {
		t.Errorf("activated_at should be cleared")
	}
}

func TestRevoke_SideBBlanksThatSide(t *testing.T) {
	db := &mockDB{rows: map[string]*linkRow{}}
	h := NewHandlerWithDB(db)
	doRequest(newRouter(h, userA), http.MethodPut, "/links/KL-T/me",
		map[string]string{"entity_id": "prog-1", "kind": "programme", "name": "P"})
	doRequest(newRouter(h, userB), http.MethodPut, "/links/KL-T/me",
		map[string]string{"entity_id": "proj-1", "kind": "project", "name": "Q"})

	w := doRequest(newRouter(h, userB), http.MethodDelete, "/links/KL-T/me", nil)
	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", w.Code)
	}
	row := db.rows["KL-T"]
	if row.SideAUserID != userA {
		t.Errorf("side A should be untouched")
	}
	if row.SideBUserID.Valid {
		t.Errorf("side B should be cleared")
	}
	if row.ActivatedAt.Valid {
		t.Errorf("activated_at should be cleared")
	}
}

func TestRevoke_NonPartyGets404(t *testing.T) {
	db := &mockDB{rows: map[string]*linkRow{}}
	h := NewHandlerWithDB(db)
	doRequest(newRouter(h, userA), http.MethodPut, "/links/KL-U/me",
		map[string]string{"entity_id": "prog-1", "kind": "programme", "name": "P"})
	w := doRequest(newRouter(h, userC), http.MethodDelete, "/links/KL-U/me", nil)
	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}

// ---------------------------------------------------------------------------
// Cascade items (Phase C)
// ---------------------------------------------------------------------------

// activateLink establishes both sides so cascade endpoints are usable.
func activateLink(h *Handler, code string) {
	doRequest(newRouter(h, userA), http.MethodPut, "/links/"+code+"/me",
		map[string]string{"entity_id": "prog-1", "kind": "programme", "name": "Big Prog"})
	doRequest(newRouter(h, userB), http.MethodPut, "/links/"+code+"/me",
		map[string]string{"entity_id": "proj-1", "kind": "project", "name": "Sub Proj"})
}

func TestCascade_PushRequiresLinkParty(t *testing.T) {
	db := &mockDB{rows: map[string]*linkRow{}}
	h := NewHandlerWithDB(db)
	activateLink(h, "KL-CP")

	// Non-party tries to push → 404.
	w := doRequest(newRouter(h, userC), http.MethodPut, "/links/KL-CP/items",
		map[string]any{
			"source_entity_id": "proj-1",
			"item_kind":        "work_package",
			"item_id":          "wp-1",
			"payload":          map[string]any{"name": "WP One"},
		})
	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for non-party push, got %d", w.Code)
	}
}

func TestCascade_PushAndPull_RoundTrip(t *testing.T) {
	db := &mockDB{rows: map[string]*linkRow{}}
	h := NewHandlerWithDB(db)
	activateLink(h, "KL-RT")

	// Side B (project) pushes a work package.
	w := doRequest(newRouter(h, userB), http.MethodPut, "/links/KL-RT/items",
		map[string]any{
			"source_entity_id": "proj-1",
			"item_kind":        "work_package",
			"item_id":          "wp-1",
			"payload":          map[string]any{"name": "WP One", "rag": "green"},
		})
	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d: %s", w.Code, w.Body.String())
	}

	// Side A (programme) pulls.
	w = doRequest(newRouter(h, userA), http.MethodGet, "/links/KL-RT/items", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var resp cascadeListResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if len(resp.Items) != 1 {
		t.Fatalf("expected 1 item, got %d", len(resp.Items))
	}
	got := resp.Items[0]
	if got.ItemID != "wp-1" || got.ItemKind != "work_package" {
		t.Errorf("unexpected key: kind=%s id=%s", got.ItemKind, got.ItemID)
	}
	if got.Deleted {
		t.Errorf("item should not be tombstoned")
	}
	if resp.Cursor == "" {
		t.Errorf("expected non-empty cursor")
	}
}

func TestCascade_PullWithSinceCursorOnlyReturnsNewItems(t *testing.T) {
	db := &mockDB{rows: map[string]*linkRow{}}
	h := NewHandlerWithDB(db)
	activateLink(h, "KL-SC")

	doRequest(newRouter(h, userB), http.MethodPut, "/links/KL-SC/items",
		map[string]any{
			"source_entity_id": "proj-1",
			"item_kind":        "work_package",
			"item_id":          "wp-1",
			"payload":          map[string]any{"name": "First"},
		})

	// First pull — receive everything + a cursor.
	w := doRequest(newRouter(h, userA), http.MethodGet, "/links/KL-SC/items", nil)
	var first cascadeListResponse
	json.NewDecoder(w.Body).Decode(&first)
	if len(first.Items) != 1 {
		t.Fatalf("expected 1 item in first pull, got %d", len(first.Items))
	}

	// Push a second item.
	time.Sleep(2 * time.Millisecond) // ensure updated_at strictly later
	doRequest(newRouter(h, userB), http.MethodPut, "/links/KL-SC/items",
		map[string]any{
			"source_entity_id": "proj-1",
			"item_kind":        "work_package",
			"item_id":          "wp-2",
			"payload":          map[string]any{"name": "Second"},
		})

	// Second pull with the prior cursor — should only return wp-2.
	w = doRequest(newRouter(h, userA), http.MethodGet,
		"/links/KL-SC/items?since="+first.Cursor, nil)
	var second cascadeListResponse
	json.NewDecoder(w.Body).Decode(&second)
	if len(second.Items) != 1 {
		t.Fatalf("expected 1 item in delta pull, got %d", len(second.Items))
	}
	if second.Items[0].ItemID != "wp-2" {
		t.Errorf("expected delta to be wp-2, got %s", second.Items[0].ItemID)
	}
}

func TestCascade_DeleteTombstonesRow(t *testing.T) {
	db := &mockDB{rows: map[string]*linkRow{}}
	h := NewHandlerWithDB(db)
	activateLink(h, "KL-DEL")

	doRequest(newRouter(h, userB), http.MethodPut, "/links/KL-DEL/items",
		map[string]any{
			"source_entity_id": "proj-1",
			"item_kind":        "work_package",
			"item_id":          "wp-1",
			"payload":          map[string]any{"name": "X"},
		})
	w := doRequest(newRouter(h, userB), http.MethodDelete,
		"/links/KL-DEL/items/work_package/wp-1", nil)
	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", w.Code)
	}

	// Receiver pulls — the row is still surfaced but flagged deleted.
	w = doRequest(newRouter(h, userA), http.MethodGet, "/links/KL-DEL/items", nil)
	var resp cascadeListResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if len(resp.Items) != 1 {
		t.Fatalf("expected 1 (tombstoned) item, got %d", len(resp.Items))
	}
	if !resp.Items[0].Deleted {
		t.Errorf("expected tombstone flag")
	}
}

func TestCascade_DeleteMissingReturns404(t *testing.T) {
	db := &mockDB{rows: map[string]*linkRow{}}
	h := NewHandlerWithDB(db)
	activateLink(h, "KL-MD")

	w := doRequest(newRouter(h, userB), http.MethodDelete,
		"/links/KL-MD/items/work_package/never-existed", nil)
	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}
