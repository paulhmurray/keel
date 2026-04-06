package auth

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

// JWTMiddleware validates the Bearer access token and injects userID + plan
// into the Gin context. Aborts with 401 on failure.
func JWTMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if !strings.HasPrefix(authHeader, "Bearer ") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing bearer token"})
			return
		}
		tokenStr := strings.TrimPrefix(authHeader, "Bearer ")

		claims, err := parseToken(tokenStr)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
			return
		}

		tokenType, _ := claims["type"].(string)
		if tokenType != "access" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "not an access token"})
			return
		}

		userID, _ := claims["sub"].(string)
		plan, _ := claims["plan"].(string)

		if userID == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token subject"})
			return
		}

		c.Set("userID", userID)
		c.Set("plan", plan)
		c.Next()
	}
}
