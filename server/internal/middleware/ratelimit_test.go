package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"golang.org/x/time/rate"
)

func init() {
	gin.SetMode(gin.TestMode)
}

func newTestRouter(rl *RateLimiter) *gin.Engine {
	r := gin.New()
	r.Use(rl.Middleware())
	r.GET("/", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})
	return r
}

func performRequest(r *gin.Engine, ip string) int {
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = ip + ":1234"
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w.Code
}

// ---------------------------------------------------------------------------
// Middleware
// ---------------------------------------------------------------------------

func TestRateLimiter_AllowsRequestWithinLimit(t *testing.T) {
	rl := NewRateLimiter(rate.Limit(10), 10)
	r := newTestRouter(rl)

	if got := performRequest(r, "1.2.3.4"); got != http.StatusOK {
		t.Errorf("expected 200, got %d", got)
	}
}

func TestRateLimiter_BlocksRequestExceedingBurst(t *testing.T) {
	// burst of 2, rate of 0 (no refill) so 3rd request is blocked
	rl := NewRateLimiter(rate.Limit(0), 2)
	r := newTestRouter(rl)

	performRequest(r, "5.5.5.5")
	performRequest(r, "5.5.5.5")
	if got := performRequest(r, "5.5.5.5"); got != http.StatusTooManyRequests {
		t.Errorf("expected 429, got %d", got)
	}
}

func TestRateLimiter_DifferentIPsHaveSeparateLimits(t *testing.T) {
	rl := NewRateLimiter(rate.Limit(0), 1)
	r := newTestRouter(rl)

	// Exhaust IP A
	performRequest(r, "10.0.0.1")
	if got := performRequest(r, "10.0.0.1"); got != http.StatusTooManyRequests {
		t.Errorf("IP A: expected 429, got %d", got)
	}

	// IP B should still be allowed (fresh bucket)
	if got := performRequest(r, "10.0.0.2"); got != http.StatusOK {
		t.Errorf("IP B: expected 200, got %d", got)
	}
}

func TestRateLimiter_BlockedResponseIsJSON(t *testing.T) {
	rl := NewRateLimiter(rate.Limit(0), 0)
	r := newTestRouter(rl)

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = "9.9.9.9:1234"
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429, got %d", w.Code)
	}
	ct := w.Header().Get("Content-Type")
	if ct == "" {
		t.Error("expected Content-Type header")
	}
	body := w.Body.String()
	if body == "" {
		t.Error("expected non-empty body")
	}
}

// ---------------------------------------------------------------------------
// getVisitor
// ---------------------------------------------------------------------------

func TestGetVisitor_CreatesNewEntryForUnknownIP(t *testing.T) {
	rl := NewRateLimiter(rate.Limit(1), 1)
	rl.getVisitor("192.168.0.1")
	rl.mu.Lock()
	_, ok := rl.visitors["192.168.0.1"]
	rl.mu.Unlock()
	if !ok {
		t.Error("expected visitor entry to be created")
	}
}

func TestGetVisitor_ReturnsSameLimiterForSameIP(t *testing.T) {
	rl := NewRateLimiter(rate.Limit(1), 1)
	l1 := rl.getVisitor("192.168.0.5")
	l2 := rl.getVisitor("192.168.0.5")
	if l1 != l2 {
		t.Error("expected same limiter instance for same IP")
	}
}

func TestGetVisitor_ReturnsDifferentLimitersForDifferentIPs(t *testing.T) {
	rl := NewRateLimiter(rate.Limit(1), 1)
	l1 := rl.getVisitor("192.168.0.10")
	l2 := rl.getVisitor("192.168.0.11")
	if l1 == l2 {
		t.Error("expected different limiter instances for different IPs")
	}
}
