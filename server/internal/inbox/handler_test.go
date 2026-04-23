package inbox

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
const testItemID = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"

func newRouter(h *Handler) *gin.Engine {
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("userID", testUserID)
		c.Next()
	})
	r.POST("/inbox", h.Create)
	r.GET("/inbox", h.List)
	r.GET("/inbox/:id/image", h.GetImage)
	r.PATCH("/inbox/:id", h.UpdateStatus)
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
// Create
// ---------------------------------------------------------------------------

func TestCreate_MissingContent_Returns400(t *testing.T) {
	w := doRequest(newRouter(&Handler{db: &mockDB{}}), http.MethodPost, "/inbox",
		map[string]string{"source": "mobile_note"})
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestCreate_InvalidBase64Image_Returns400(t *testing.T) {
	db := &mockDB{}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodPost, "/inbox",
		map[string]string{"content": "hello", "image_data": "!!!not-base64!!!"})
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
}

func TestCreate_DefaultsSourceToMobileNote(t *testing.T) {
	var capturedSource string
	now := time.Now().UTC()
	db := &mockDB{
		queryRowFn: func(_ context.Context, sql string, args ...any) pgx.Row {
			// args: userID, projectID, source, content, imageBytes, caption
			if len(args) >= 3 {
				capturedSource = args[2].(string)
			}
			return &mockRow{values: []any{testItemID, now}}
		},
	}
	doRequest(newRouter(&Handler{db: db}), http.MethodPost, "/inbox",
		map[string]string{"content": "note text"})
	if capturedSource != "mobile_note" {
		t.Errorf("expected source 'mobile_note', got %q", capturedSource)
	}
}

func TestCreate_Success(t *testing.T) {
	now := time.Now().UTC()
	db := &mockDB{
		queryRowFn: func(_ context.Context, _ string, _ ...any) pgx.Row {
			return &mockRow{values: []any{testItemID, now}}
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodPost, "/inbox",
		map[string]string{"content": "important note", "source": "test"})
	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", w.Code, w.Body.String())
	}
	var resp createResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.ID != testItemID {
		t.Errorf("expected id %q, got %q", testItemID, resp.ID)
	}
}

func TestCreate_WithValidBase64Image_Succeeds(t *testing.T) {
	now := time.Now().UTC()
	db := &mockDB{
		queryRowFn: func(_ context.Context, _ string, _ ...any) pgx.Row {
			return &mockRow{values: []any{testItemID, now}}
		},
	}
	imgB64 := base64.StdEncoding.EncodeToString([]byte("fake-image-bytes"))
	w := doRequest(newRouter(&Handler{db: db}), http.MethodPost, "/inbox",
		map[string]string{"content": "photo", "image_data": imgB64})
	if w.Code != http.StatusCreated {
		t.Errorf("expected 201, got %d: %s", w.Code, w.Body.String())
	}
}

// ---------------------------------------------------------------------------
// List
// ---------------------------------------------------------------------------

func TestList_ReturnsEmptyList(t *testing.T) {
	db := &mockDB{
		queryFn: func(_ context.Context, _ string, _ ...any) (pgx.Rows, error) {
			return &mockRows{}, nil
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodGet, "/inbox", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var result []any
	json.NewDecoder(w.Body).Decode(&result)
	if len(result) != 0 {
		t.Errorf("expected empty list, got %v", result)
	}
}

func TestList_ReturnsPendingByDefault(t *testing.T) {
	var capturedStatus string
	db := &mockDB{
		queryFn: func(_ context.Context, sql string, args ...any) (pgx.Rows, error) {
			if len(args) >= 2 {
				capturedStatus = args[1].(string)
			}
			return &mockRows{}, nil
		},
	}
	doRequest(newRouter(&Handler{db: db}), http.MethodGet, "/inbox", nil)
	if capturedStatus != "pending" {
		t.Errorf("expected default status 'pending', got %q", capturedStatus)
	}
}

func TestList_RespectsStatusQueryParam(t *testing.T) {
	var capturedStatus string
	db := &mockDB{
		queryFn: func(_ context.Context, _ string, args ...any) (pgx.Rows, error) {
			if len(args) >= 2 {
				capturedStatus = args[1].(string)
			}
			return &mockRows{}, nil
		},
	}
	req := httptest.NewRequest(http.MethodGet, "/inbox?status=accepted", nil)
	w := httptest.NewRecorder()
	newRouter(&Handler{db: db}).ServeHTTP(w, req)
	if capturedStatus != "accepted" {
		t.Errorf("expected status 'accepted', got %q", capturedStatus)
	}
}

func TestList_ReturnsList(t *testing.T) {
	now := time.Now().UTC()
	var caption *string
	db := &mockDB{
		queryFn: func(_ context.Context, _ string, _ ...any) (pgx.Rows, error) {
			return &mockRows{data: [][]any{
				{testItemID, "mobile_note", "some content", caption, "pending", now},
			}}, nil
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodGet, "/inbox", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var result []map[string]any
	json.NewDecoder(w.Body).Decode(&result)
	if len(result) != 1 {
		t.Fatalf("expected 1 item, got %d", len(result))
	}
	if result[0]["id"] != testItemID {
		t.Errorf("item id = %v, want %v", result[0]["id"], testItemID)
	}
}

// ---------------------------------------------------------------------------
// UpdateStatus
// ---------------------------------------------------------------------------

func TestUpdateStatus_InvalidStatus_Returns400(t *testing.T) {
	w := doRequest(newRouter(&Handler{db: &mockDB{}}), http.MethodPatch,
		"/inbox/"+testItemID, map[string]string{"status": "unknown"})
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestUpdateStatus_MissingStatus_Returns400(t *testing.T) {
	w := doRequest(newRouter(&Handler{db: &mockDB{}}), http.MethodPatch,
		"/inbox/"+testItemID, map[string]string{})
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestUpdateStatus_NotFound_Returns404(t *testing.T) {
	db := &mockDB{
		execFn: func(_ context.Context, _ string, _ ...any) (pgconn.CommandTag, error) {
			return pgconn.NewCommandTag("UPDATE 0"), nil
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodPatch,
		"/inbox/"+testItemID, map[string]string{"status": "accepted"})
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d", w.Code)
	}
}

func TestUpdateStatus_Accepted_Returns200(t *testing.T) {
	db := &mockDB{
		execFn: func(_ context.Context, _ string, _ ...any) (pgconn.CommandTag, error) {
			return pgconn.NewCommandTag("UPDATE 1"), nil
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodPatch,
		"/inbox/"+testItemID, map[string]string{"status": "accepted"})
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var resp map[string]any
	json.NewDecoder(w.Body).Decode(&resp)
	if resp["status"] != "accepted" {
		t.Errorf("expected status 'accepted', got %v", resp["status"])
	}
}

func TestUpdateStatus_Rejected_Returns200(t *testing.T) {
	db := &mockDB{
		execFn: func(_ context.Context, _ string, _ ...any) (pgconn.CommandTag, error) {
			return pgconn.NewCommandTag("UPDATE 1"), nil
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodPatch,
		"/inbox/"+testItemID, map[string]string{"status": "rejected"})
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
}

// ---------------------------------------------------------------------------
// GetImage
// ---------------------------------------------------------------------------

func TestGetImage_NotFound_Returns404(t *testing.T) {
	db := &mockDB{
		queryRowFn: func(_ context.Context, _ string, _ ...any) pgx.Row {
			return &mockRow{err: errors.New("no rows")}
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodGet,
		"/inbox/"+testItemID+"/image", nil)
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d", w.Code)
	}
}

func TestGetImage_NoImageData_Returns404(t *testing.T) {
	db := &mockDB{
		queryRowFn: func(_ context.Context, _ string, _ ...any) pgx.Row {
			return &mockRow{values: []any{[]byte{}}}
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodGet,
		"/inbox/"+testItemID+"/image", nil)
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d", w.Code)
	}
}

func TestGetImage_Success(t *testing.T) {
	imageData := []byte{0xFF, 0xD8, 0xFF, 0xE0} // JPEG magic bytes
	db := &mockDB{
		queryRowFn: func(_ context.Context, _ string, _ ...any) pgx.Row {
			return &mockRow{values: []any{imageData}}
		},
	}
	w := doRequest(newRouter(&Handler{db: db}), http.MethodGet,
		"/inbox/"+testItemID+"/image", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	if ct := w.Header().Get("Content-Type"); ct != "image/jpeg" {
		t.Errorf("expected Content-Type image/jpeg, got %q", ct)
	}
	if !bytes.Equal(w.Body.Bytes(), imageData) {
		t.Error("response body does not match image data")
	}
}
