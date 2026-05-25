// Package version serves the latest Keel release info to the desktop app.
//
// The source of truth is GitHub Releases — whenever a `v*` tag is pushed
// and a release is published at github.com/paulhmurray/keel, this package
// will surface it via the /version/latest endpoint within ~10 minutes
// (cache TTL). No manual server config is needed per release.
//
// Env-var fallback (KEEL_LATEST_VERSION, KEEL_RELEASE_NOTES) is preserved
// for the case where GitHub is unreachable on a cold start.
package version

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

const (
	githubLatestURL = "https://api.github.com/repos/paulhmurray/keel/releases/latest"
	githubTimeout   = 5 * time.Second
	cacheTTL        = 10 * time.Minute
	githubOwnerRepo = "paulhmurray/keel"
	userAgent       = "keel-sync"
)

// Info is the cached representation of a release.
type Info struct {
	Version      string // e.g. "1.1.8" (no leading "v")
	ReleaseNotes string
}

// Service serves release info with a TTL cache and graceful fallback.
type Service struct {
	httpClient *http.Client

	mu        sync.RWMutex
	cached    Info
	cachedAt  time.Time
	hasCached bool // distinguishes a real successful fetch from zero-value
}

// NewService returns a Service ready to use. The HTTP client has a short
// timeout — the version endpoint is on the hot path for app startup, and
// we'd rather serve stale/fallback data than block.
func NewService() *Service {
	return &Service{
		httpClient: &http.Client{Timeout: githubTimeout},
	}
}

// Latest returns the latest release info, refreshing from GitHub if the
// cache has expired. On any GitHub failure it serves stale cache (if any)
// or the env-var fallback. It never returns an error — the endpoint is a
// courtesy and must not break startup.
func (s *Service) Latest(ctx context.Context) Info {
	s.mu.RLock()
	cached, cachedAt, hasCached := s.cached, s.cachedAt, s.hasCached
	s.mu.RUnlock()

	if hasCached && time.Since(cachedAt) < cacheTTL {
		return cached
	}

	fresh, err := s.fetchFromGitHub(ctx)
	if err == nil {
		s.mu.Lock()
		s.cached = fresh
		s.cachedAt = time.Now()
		s.hasCached = true
		s.mu.Unlock()
		return fresh
	}

	log.Printf("version: GitHub fetch failed (%v); falling back", err)

	if hasCached {
		// Extend the stale cache's lifetime so we don't retry on every
		// request during a sustained outage.
		s.mu.Lock()
		s.cachedAt = time.Now()
		s.mu.Unlock()
		return cached
	}

	// Cold start + GitHub down. Use env vars; cache them briefly.
	fallback := Info{
		Version:      envOrDefault("KEEL_LATEST_VERSION", "1.0.0"),
		ReleaseNotes: os.Getenv("KEEL_RELEASE_NOTES"),
	}
	s.mu.Lock()
	s.cached = fallback
	s.cachedAt = time.Now()
	s.hasCached = true
	s.mu.Unlock()
	return fallback
}

// DownloadURLs returns the per-platform download URLs for a given version.
// Asset filenames are stable per .github/workflows/release.yml and
// codemagic.yaml — if those ever change, update here.
func DownloadURLs(version string) map[string]string {
	base := fmt.Sprintf("https://github.com/%s/releases/download/v%s", githubOwnerRepo, version)
	return map[string]string{
		"linux":   base + "/keel-linux.tar.gz",
		"windows": base + "/keel-windows-setup.exe",
		"macos":   base + "/keel-macos.dmg",
	}
}

func (s *Service) fetchFromGitHub(ctx context.Context) (Info, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, githubLatestURL, nil)
	if err != nil {
		return Info{}, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	req.Header.Set("User-Agent", userAgent)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return Info{}, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return Info{}, fmt.Errorf("github status %d", resp.StatusCode)
	}

	var payload struct {
		TagName    string `json:"tag_name"`
		Body       string `json:"body"`
		Draft      bool   `json:"draft"`
		Prerelease bool   `json:"prerelease"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return Info{}, err
	}
	if payload.Draft || payload.Prerelease {
		return Info{}, fmt.Errorf("latest release is draft/prerelease")
	}
	version := strings.TrimPrefix(payload.TagName, "v")
	if version == "" {
		return Info{}, fmt.Errorf("empty tag_name")
	}
	return Info{Version: version, ReleaseNotes: payload.Body}, nil
}

func envOrDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
