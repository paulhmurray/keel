package auth

import (
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func newTestRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	protected := r.Group("")
	protected.Use(JWTMiddleware())
	protected.GET("/protected", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"user_id": c.GetString("userID"),
			"plan":    c.GetString("plan"),
		})
	})
	return r
}

func doGet(r *gin.Engine, path, bearerToken string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	if bearerToken != "" {
		req.Header.Set("Authorization", "Bearer "+bearerToken)
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestJWTMiddleware_ValidAccessToken_Returns200(t *testing.T) {
	os.Setenv("JWT_SECRET", "test-secret-key-minimum-32-chars!!")
	token, err := generateAccessToken("user-123", "solo")
	if err != nil {
		t.Fatalf("generateAccessToken failed: %v", err)
	}

	w := doGet(newTestRouter(), "/protected", token)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
}

func TestJWTMiddleware_InjectsUserIDAndPlan(t *testing.T) {
	os.Setenv("JWT_SECRET", "test-secret-key-minimum-32-chars!!")
	token, _ := generateAccessToken("user-abc", "solo")

	w := doGet(newTestRouter(), "/protected", token)

	body := w.Body.String()
	if !strings.Contains(body, "user-abc") {
		t.Errorf("response should contain userID, got: %s", body)
	}
	if !strings.Contains(body, "solo") {
		t.Errorf("response should contain plan, got: %s", body)
	}
}

func TestJWTMiddleware_MissingToken_Returns401(t *testing.T) {
	os.Setenv("JWT_SECRET", "test-secret-key-minimum-32-chars!!")
	w := doGet(newTestRouter(), "/protected", "")

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}
}

func TestJWTMiddleware_MalformedToken_Returns401(t *testing.T) {
	os.Setenv("JWT_SECRET", "test-secret-key-minimum-32-chars!!")
	w := doGet(newTestRouter(), "/protected", "not.a.real.jwt")

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}
}

func TestJWTMiddleware_RefreshToken_Returns401(t *testing.T) {
	os.Setenv("JWT_SECRET", "test-secret-key-minimum-32-chars!!")
	_, refresh, err := generateTokenPair("user-456", "free")
	if err != nil {
		t.Fatalf("generateTokenPair failed: %v", err)
	}

	w := doGet(newTestRouter(), "/protected", refresh)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for refresh token, got %d: %s", w.Code, w.Body.String())
	}
}

func TestJWTMiddleware_WrongSecret_Returns401(t *testing.T) {
	os.Setenv("JWT_SECRET", "original-secret-key-minimum-32!!")
	token, _ := generateAccessToken("user-789", "free")

	os.Setenv("JWT_SECRET", "different-secret-key-minimum-32!")
	defer os.Setenv("JWT_SECRET", "test-secret-key-minimum-32-chars!!")

	w := doGet(newTestRouter(), "/protected", token)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for wrong secret, got %d", w.Code)
	}
}

func TestJWTMiddleware_ErrorResponseIsJSON(t *testing.T) {
	os.Setenv("JWT_SECRET", "test-secret-key-minimum-32-chars!!")
	w := doGet(newTestRouter(), "/protected", "")

	ct := w.Header().Get("Content-Type")
	if !strings.Contains(ct, "application/json") {
		t.Errorf("expected JSON content-type, got %q", ct)
	}
	if !strings.Contains(w.Body.String(), "error") {
		t.Errorf("error response should contain 'error' key, got: %s", w.Body.String())
	}
}

func TestJWTMiddleware_BearerPrefixRequired(t *testing.T) {
	os.Setenv("JWT_SECRET", "test-secret-key-minimum-32-chars!!")
	token, _ := generateAccessToken("user-id", "free")

	// Send without "Bearer " prefix
	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	req.Header.Set("Authorization", token) // no "Bearer " prefix
	w := httptest.NewRecorder()
	newTestRouter().ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 without Bearer prefix, got %d", w.Code)
	}
}
