package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

type claims struct {
	Name string `json:"name"`
	jwt.RegisteredClaims
}

// JWT validates the Bearer token from Authorization header or ?token= query param.
// Sets "userID" and "userName" in the Gin context.
func JWT(secret string) gin.HandlerFunc {
	key := []byte(secret)

	return func(c *gin.Context) {
		raw := c.GetHeader("Authorization")
		if raw == "" {
			raw = c.Query("token") // WebSocket uses query param
		} else {
			raw = strings.TrimPrefix(raw, "Bearer ")
		}

		if raw == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing token"})
			return
		}

		var cl claims
		tok, err := jwt.ParseWithClaims(raw, &cl, func(t *jwt.Token) (any, error) {
			if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, jwt.ErrSignatureInvalid
			}
			return key, nil
		})

		if err != nil || !tok.Valid {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
			return
		}

		c.Set("userID", cl.Subject)
		c.Set("userName", cl.Name)
		c.Next()
	}
}
