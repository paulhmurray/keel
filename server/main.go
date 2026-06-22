package main

import (
	"context"
	"embed"
	"io/fs"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/time/rate"

	"github.com/keel/server/internal/auth"
	"github.com/keel/server/internal/billing"
	serverdb "github.com/keel/server/internal/db"
	"github.com/keel/server/internal/inbox"
	"github.com/keel/server/internal/links"
	"github.com/keel/server/internal/middleware"
	"github.com/keel/server/internal/sync"
	"github.com/keel/server/internal/version"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

func main() {
	_, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Build migrations map from embedded FS
	migrations := make(map[string]string)
	err := fs.WalkDir(migrationsFS, "migrations", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || !strings.HasSuffix(path, ".sql") {
			return nil
		}
		content, err := migrationsFS.ReadFile(path)
		if err != nil {
			return err
		}
		// Use only the filename as key for sorting
		parts := strings.Split(path, "/")
		migrations[parts[len(parts)-1]] = string(content)
		return nil
	})
	if err != nil {
		log.Fatalf("failed to read migrations: %v", err)
	}

	db, err := serverdb.Connect(context.Background(), migrations)
	if err != nil {
		log.Fatalf("failed to connect to database: %v", err)
	}
	defer db.Close()

	log.Println("database connected and migrations applied")

	// Check required env vars
	if os.Getenv("JWT_SECRET") == "" {
		log.Fatal("JWT_SECRET environment variable is required")
	}

	// Set Gin mode
	if os.Getenv("GIN_MODE") == "" {
		gin.SetMode(gin.ReleaseMode)
	}

	// 30 requests per minute per IP, burst of 10
	rateLimiter := middleware.NewRateLimiter(rate.Every(2*time.Second), 10)

	router := gin.New()
	router.Use(gin.Logger())
	router.Use(gin.Recovery())
	router.Use(rateLimiter.Middleware())

	// Health check
	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	// Version endpoint — no auth required.
	// Source of truth is GitHub Releases (paulhmurray/keel). Cached 10 min.
	// Falls back to KEEL_LATEST_VERSION / KEEL_RELEASE_NOTES env vars if
	// GitHub is unreachable on a cold start.
	versionService := version.NewService()
	router.GET("/version/latest", func(c *gin.Context) {
		info := versionService.Latest(c.Request.Context())
		c.JSON(http.StatusOK, gin.H{
			"version":         info.Version,
			"release_notes":   info.ReleaseNotes,
			"download_url":    version.DownloadURLs(info.Version),
			"minimum_version": "1.0.0",
			"critical":        false,
		})
	})

	// Handlers
	authHandler := auth.NewHandler(db)
	syncHandler := sync.NewHandler(db)
	billingHandler := billing.NewHandler(db)
	inboxHandler := inbox.NewHandler(db)
	linksHandler := links.NewHandler(db)

	// Auth routes (no JWT required)
	authGroup := router.Group("/auth")
	{
		authGroup.POST("/register", authHandler.Register)
		authGroup.POST("/login", authHandler.Login)
		authGroup.POST("/refresh", authHandler.Refresh)
	}

	// Billing webhook — no auth, Stripe validates signature internally
	router.POST("/billing/webhook", billingHandler.Webhook)

	// Protected routes
	protected := router.Group("")
	protected.Use(auth.JWTMiddleware())
	{
		// Sync routes
		projects := protected.Group("/projects")
		{
			projects.GET("", syncHandler.ListProjects)
			projects.POST("", syncHandler.CreateProject)
			projects.PUT("/:id", syncHandler.UpdateProject)
			projects.DELETE("/:id", syncHandler.DeleteProject)
			projects.POST("/:id/sync", syncHandler.PushSync)
			projects.GET("/:id/sync", syncHandler.PullSync)
		}

		// Billing
		protected.POST("/billing/checkout", billingHandler.Checkout)
		protected.GET("/billing/portal", billingHandler.Portal)

		// Inbox relay
		protected.POST("/inbox", inboxHandler.Create)
		protected.GET("/inbox", inboxHandler.List)
		protected.GET("/inbox/:id/image", inboxHandler.GetImage)
		protected.PATCH("/inbox/:id", inboxHandler.UpdateStatus)

		// Programme links (Phase B). Bearer-code based: anyone with
		// the code can claim the opposite side, the server enforces
		// kind-complementarity + party limits.
		linksGroup := protected.Group("/links")
		{
			linksGroup.PUT("/:code/me", linksHandler.ClaimSide)
			linksGroup.GET("/:code", linksHandler.GetLink)
			linksGroup.DELETE("/:code/me", linksHandler.RevokeSide)
			// Cascade items (Phase C) — structural project data
			// flowing into the link channel.
			linksGroup.PUT("/:code/items", linksHandler.PushCascadeItem)
			linksGroup.GET("/:code/items", linksHandler.PullCascadeItems)
			linksGroup.DELETE("/:code/items/:kind/:id", linksHandler.DeleteCascadeItem)
		}
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("keel sync server listening on :%s", port)
	if err := router.Run(":" + port); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
