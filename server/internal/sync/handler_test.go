package sync

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"reflect"
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
	queryRowFn func(ctx context.Context, sql string, args ...any) pgx.Row
	queryFn    func(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	execFn     func(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}

func (m *mockDB) QueryRow(ctx context.Context, sql string, args ...any) pgx.Row {
	if m.queryRowFn != nil {
		return m.queryRowFn(ctx, sql, args...)
	}
	return &mockRow{err: errors.New("unexpected QueryRow")}
}
func (m *mockDB) Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error) {
	if m.queryFn != nil {
		return m.queryFn(ctx, sql, args...)
	}
	return nil, errors.New("unexpected Query")
}
func (m *mockDB) Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error) {
	if m.execFn != nil {
		return m.execFn(ctx, sql, args...)
	}
	return pgconn.NewCommandTag(""), errors.New("unexpected Exec")
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

// mockRows implements pgx.Rows
type mockRows struct {
	data [][]any
	pos  int
	err  error
}

func (r *mockRows) Next() bool                                   { r.pos++; return r.pos <= len(r.data) }
func (r *mockRows) Close()                                       {}
func (r *mockRows) Err() error                                   { return r.err }
func (r *mockRows) CommandTag() pgconn.CommandTag                { return pgconn.NewCommandTag("") }
func (r *mockRows) FieldDescriptions() []pgconn.FieldDescription { return nil }
func (r *mockRows) Values() ([]any, error)                       { return nil, nil }
func (r *mockRows) RawValues() [][]byte                          { return nil }
func (r *mockRows) Conn() *pgx.Conn                              { return nil }
func (r *mockRows) Scan(dest ...any) error {
	if r.err != nil {
		return r.err
	}
	row := r.data[r.pos-1]
	for i, d := range dest {
		if i >= len(row) {
			break
		}
		reflect.ValueOf(d).Elem().Set(reflect.ValueOf(row[i]))
	}
	return nil
}

// ---------------------------------------------------------------------------
// Test router helpers
// ---------------------------------------------------------------------------

const testUserID = "550e8400-e29b-41d4-a716-446655440000"
const testProjectID = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"

func newRouter(h *Handler) *gin.Engine {
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("userID", testUserID)
		c.Next()
	})
	r.GET("/projects", h.ListProjects)
	r.POST("/projects", h.CreateProject)
	r.PUT("/projects/:id", h.UpdateProject)
	r.DELETE("/projects/:id", h.DeleteProject)
	r.POST("/projects/:id/sync", h.PushSync)
	r.GET("/projects/:id/sync", h.PullSync)
	return r
}

func doRequest(r *gin.Engine, method, path string, body any) *httptest.ResponseRecorder {
	var buf bytes.Buffer
	if body != nil {
		if s, ok := body.(string); ok {
			buf.WriteString(s)
		} else {
			json.NewEncoder(&buf).Encode(body)
		}
	}
	req := httptest.NewRequest(method, path, &buf)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

// ---------------------------------------------------------------------------
// ListProjects
// ---------------------------------------------------------------------------

func TestListProjects_ReturnsEmptyList(t *testing.T) {
	db := &mockDB{
		queryFn: func(_ context.Context, _ string, _ ...any) (pgx.Rows, error) {
			return &mockRows{}, nil
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodGet, "/projects", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var result []any
	json.NewDecoder(w.Body).Decode(&result)
	if len(result) != 0 {
		t.Errorf("expected empty list, got %v", result)
	}
}

func TestListProjects_ReturnsList(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Second)
	db := &mockDB{
		queryFn: func(_ context.Context, _ string, _ ...any) (pgx.Rows, error) {
			return &mockRows{data: [][]any{
				{testProjectID, "My Project", now},
			}}, nil
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodGet, "/projects", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var result []map[string]any
	json.NewDecoder(w.Body).Decode(&result)
	if len(result) != 1 {
		t.Fatalf("expected 1 project, got %d", len(result))
	}
	if result[0]["id"] != testProjectID {
		t.Errorf("project id = %v, want %v", result[0]["id"], testProjectID)
	}
}

func TestListProjects_DBError_Returns500(t *testing.T) {
	db := &mockDB{
		queryFn: func(_ context.Context, _ string, _ ...any) (pgx.Rows, error) {
			return nil, errors.New("db error")
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodGet, "/projects", nil)
	if w.Code != http.StatusInternalServerError {
		t.Errorf("expected 500, got %d", w.Code)
	}
}

// ---------------------------------------------------------------------------
// CreateProject
// ---------------------------------------------------------------------------

func TestCreateProject_Success(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Second)
	db := &mockDB{
		queryRowFn: func(_ context.Context, _ string, _ ...any) pgx.Row {
			return &mockRow{values: []any{testProjectID, now}}
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodPost, "/projects",
		map[string]string{"id": testProjectID, "name": "Test Project"})
	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", w.Code, w.Body.String())
	}
}

func TestCreateProject_InvalidUUID_Returns400(t *testing.T) {
	db := &mockDB{}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodPost, "/projects",
		map[string]string{"id": "not-a-uuid", "name": "Test"})
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestCreateProject_MissingName_Returns400(t *testing.T) {
	db := &mockDB{}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodPost, "/projects",
		map[string]string{"id": testProjectID})
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestCreateProject_MissingID_Returns400(t *testing.T) {
	db := &mockDB{}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodPost, "/projects",
		map[string]string{"name": "Test Project"})
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

// ---------------------------------------------------------------------------
// UpdateProject
// ---------------------------------------------------------------------------

func TestUpdateProject_InvalidUUID_Returns400(t *testing.T) {
	w := doRequest(newRouter(&Handler{db: &mockDB{}}), http.MethodPut,
		"/projects/not-a-uuid", map[string]string{"name": "x"})
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestUpdateProject_NotFound_Returns404(t *testing.T) {
	db := &mockDB{
		execFn: func(_ context.Context, _ string, _ ...any) (pgconn.CommandTag, error) {
			return pgconn.NewCommandTag("UPDATE 0"), nil
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodPut,
		"/projects/"+testProjectID, map[string]string{"name": "New Name"})
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d", w.Code)
	}
}

func TestUpdateProject_Success(t *testing.T) {
	db := &mockDB{
		execFn: func(_ context.Context, _ string, _ ...any) (pgconn.CommandTag, error) {
			return pgconn.NewCommandTag("UPDATE 1"), nil
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodPut,
		"/projects/"+testProjectID, map[string]string{"name": "New Name"})
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
}

// ---------------------------------------------------------------------------
// DeleteProject
// ---------------------------------------------------------------------------

func TestDeleteProject_InvalidUUID_Returns400(t *testing.T) {
	w := doRequest(newRouter(&Handler{db: &mockDB{}}), http.MethodDelete,
		"/projects/bad-id", nil)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestDeleteProject_NotFound_Returns404(t *testing.T) {
	db := &mockDB{
		execFn: func(_ context.Context, _ string, _ ...any) (pgconn.CommandTag, error) {
			return pgconn.NewCommandTag("DELETE 0"), nil
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodDelete,
		"/projects/"+testProjectID, nil)
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d", w.Code)
	}
}

func TestDeleteProject_Success(t *testing.T) {
	db := &mockDB{
		execFn: func(_ context.Context, _ string, _ ...any) (pgconn.CommandTag, error) {
			return pgconn.NewCommandTag("DELETE 1"), nil
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodDelete,
		"/projects/"+testProjectID, nil)
	if w.Code != http.StatusNoContent {
		t.Errorf("expected 204, got %d", w.Code)
	}
}

// ---------------------------------------------------------------------------
// PushSync
// ---------------------------------------------------------------------------

func TestPushSync_InvalidUUID_Returns400(t *testing.T) {
	// requireSoloPlan is called first — give it a solo plan so UUID check fires
	db := &mockDB{
		queryRowFn: func(_ context.Context, _ string, _ ...any) pgx.Row {
			return &mockRow{values: []any{"solo"}}
		},
	}
	req := httptest.NewRequest(http.MethodPost, "/projects/not-a-uuid/sync",
		bytes.NewBufferString("data"))
	req.Header.Set("Content-Type", "application/octet-stream")
	w := httptest.NewRecorder()
	newRouter(&Handler{db: db}).ServeHTTP(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestPushSync_NotSoloPlan_Returns403(t *testing.T) {
	db := &mockDB{
		queryRowFn: func(_ context.Context, _ string, _ ...any) pgx.Row {
			return &mockRow{values: []any{"free"}}
		},
	}
	req := httptest.NewRequest(http.MethodPost, "/projects/"+testProjectID+"/sync",
		bytes.NewBufferString("data"))
	w := httptest.NewRecorder()
	newRouter(&Handler{db: db}).ServeHTTP(w, req)
	if w.Code != http.StatusForbidden {
		t.Errorf("expected 403, got %d: %s", w.Code, w.Body.String())
	}
}

func TestPushSync_InvalidBase64_Returns400(t *testing.T) {
	callCount := 0
	now := time.Now().UTC()
	db := &mockDB{
		queryRowFn: func(_ context.Context, _ string, _ ...any) pgx.Row {
			callCount++
			switch callCount {
			case 1: // requireSoloPlan
				return &mockRow{values: []any{"solo"}}
			case 2: // ownership check
				return &mockRow{values: []any{true}}
			default:
				return &mockRow{values: []any{now}}
			}
		},
	}
	req := httptest.NewRequest(http.MethodPost, "/projects/"+testProjectID+"/sync",
		bytes.NewBufferString("!!!not-base64!!!"))
	req.Header.Set("Content-Type", "application/octet-stream")
	w := httptest.NewRecorder()
	newRouter(&Handler{db: db}).ServeHTTP(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
}

func TestPushSync_Success(t *testing.T) {
	now := time.Now().UTC()
	callCount := 0
	db := &mockDB{
		queryRowFn: func(_ context.Context, _ string, _ ...any) pgx.Row {
			callCount++
			switch callCount {
			case 1: // requireSoloPlan
				return &mockRow{values: []any{"solo"}}
			case 2: // ownership check
				return &mockRow{values: []any{true}}
			default: // store sync data
				return &mockRow{values: []any{now}}
			}
		},
	}
	payload := base64.StdEncoding.EncodeToString([]byte("encrypted-bytes"))
	req := httptest.NewRequest(http.MethodPost, "/projects/"+testProjectID+"/sync",
		bytes.NewBufferString(payload))
	req.Header.Set("Content-Type", "application/octet-stream")
	w := httptest.NewRecorder()
	newRouter(&Handler{db: db}).ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
}

// ---------------------------------------------------------------------------
// PullSync
// ---------------------------------------------------------------------------

func TestPullSync_InvalidUUID_Returns400(t *testing.T) {
	db := &mockDB{
		queryRowFn: func(_ context.Context, _ string, _ ...any) pgx.Row {
			return &mockRow{values: []any{"solo"}}
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodGet,
		"/projects/not-a-uuid/sync", nil)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestPullSync_NoSyncData_Returns404(t *testing.T) {
	callCount := 0
	db := &mockDB{
		queryRowFn: func(_ context.Context, _ string, _ ...any) pgx.Row {
			callCount++
			if callCount == 1 {
				return &mockRow{values: []any{"solo"}}
			}
			// encrypted_data is nil
			return &mockRow{values: []any{[]byte(nil), time.Now().UTC()}}
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodGet,
		"/projects/"+testProjectID+"/sync", nil)
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d: %s", w.Code, w.Body.String())
	}
}

func TestPullSync_Success(t *testing.T) {
	now := time.Now().UTC()
	encrypted := []byte("some-encrypted-data")
	callCount := 0
	db := &mockDB{
		queryRowFn: func(_ context.Context, _ string, _ ...any) pgx.Row {
			callCount++
			if callCount == 1 {
				return &mockRow{values: []any{"solo"}}
			}
			return &mockRow{values: []any{encrypted, now}}
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodGet,
		"/projects/"+testProjectID+"/sync", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var result map[string]any
	json.NewDecoder(w.Body).Decode(&result)
	if result["encrypted_data"] == nil {
		t.Error("expected encrypted_data in response")
	}
}
