package auth

import (
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

type Handler struct {
	db *pgxpool.Pool
}

func NewHandler(db *pgxpool.Pool) *Handler {
	return &Handler{db: db}
}

type registerRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=8"`
}

type loginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

type authResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	UserID       string `json:"user_id"`
	Plan         string `json:"plan"`
}

// Register handles POST /auth/register
func (h *Handler) Register(c *gin.Context) {
	var req registerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), 12)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
		return
	}

	var userID, plan string
	err = h.db.QueryRow(c.Request.Context(),
		`INSERT INTO users (email, password_hash) VALUES ($1, $2)
		 RETURNING id, plan`,
		req.Email, string(hash),
	).Scan(&userID, &plan)
	if err != nil {
		if strings.Contains(err.Error(), "unique") || strings.Contains(err.Error(), "duplicate") {
			c.JSON(http.StatusConflict, gin.H{"error": "email already registered"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create user"})
		return
	}

	access, refresh, err := generateTokenPair(userID, plan)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate tokens"})
		return
	}

	c.JSON(http.StatusCreated, authResponse{
		AccessToken:  access,
		RefreshToken: refresh,
		UserID:       userID,
		Plan:         plan,
	})
}

// Login handles POST /auth/login
func (h *Handler) Login(c *gin.Context) {
	var req loginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var userID, passwordHash, plan string
	err := h.db.QueryRow(c.Request.Context(),
		`SELECT id, password_hash, plan FROM users WHERE email = $1`,
		req.Email,
	).Scan(&userID, &passwordHash, &plan)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid email or password"})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid email or password"})
		return
	}

	access, refresh, err := generateTokenPair(userID, plan)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate tokens"})
		return
	}

	c.JSON(http.StatusOK, authResponse{
		AccessToken:  access,
		RefreshToken: refresh,
		UserID:       userID,
		Plan:         plan,
	})
}

// Refresh handles POST /auth/refresh — requires valid refresh token in Bearer header
func (h *Handler) Refresh(c *gin.Context) {
	authHeader := c.GetHeader("Authorization")
	if !strings.HasPrefix(authHeader, "Bearer ") {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing bearer token"})
		return
	}
	tokenStr := strings.TrimPrefix(authHeader, "Bearer ")

	claims, err := parseToken(tokenStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
		return
	}

	// Validate it is a refresh token
	tokenType, _ := claims["type"].(string)
	if tokenType != "refresh" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "not a refresh token"})
		return
	}

	userID, _ := claims["sub"].(string)
	if _, err := uuid.Parse(userID); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token subject"})
		return
	}

	// Fetch latest plan from DB (it may have changed)
	var plan string
	err = h.db.QueryRow(c.Request.Context(),
		`SELECT plan FROM users WHERE id = $1`, userID,
	).Scan(&plan)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
		return
	}

	accessToken, err := generateAccessToken(userID, plan)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"access_token": accessToken})
}

// generateTokenPair creates both an access token (24h) and a refresh token (30d).
func generateTokenPair(userID, plan string) (string, string, error) {
	access, err := generateAccessToken(userID, plan)
	if err != nil {
		return "", "", err
	}

	secret := []byte(os.Getenv("JWT_SECRET"))
	refreshClaims := jwt.MapClaims{
		"sub":  userID,
		"plan": plan,
		"type": "refresh",
		"exp":  time.Now().Add(30 * 24 * time.Hour).Unix(),
		"iat":  time.Now().Unix(),
	}
	refreshToken := jwt.NewWithClaims(jwt.SigningMethodHS256, refreshClaims)
	refresh, err := refreshToken.SignedString(secret)
	if err != nil {
		return "", "", err
	}

	return access, refresh, nil
}

// generateAccessToken creates a 24h access token.
func generateAccessToken(userID, plan string) (string, error) {
	secret := []byte(os.Getenv("JWT_SECRET"))
	claims := jwt.MapClaims{
		"sub":  userID,
		"plan": plan,
		"type": "access",
		"exp":  time.Now().Add(24 * time.Hour).Unix(),
		"iat":  time.Now().Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(secret)
}

// parseToken validates and parses a JWT, returning its claims.
func parseToken(tokenStr string) (jwt.MapClaims, error) {
	secret := []byte(os.Getenv("JWT_SECRET"))
	token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, jwt.ErrSignatureInvalid
		}
		return secret, nil
	}, jwt.WithValidMethods([]string{"HS256"}))
	if err != nil {
		return nil, err
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || !token.Valid {
		return nil, jwt.ErrTokenInvalidClaims
	}
	return claims, nil
}
