package middleware

import (
	"net/http"
	"strings"

	"taskly-server/internal/config"
	"taskly-server/internal/models"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v4"
)

type Claims struct {
	UserID uint `json:"user_id"`
	jwt.RegisteredClaims
}

func AuthRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, models.Fail(401, "unauthorized"))
			return
		}
		tokenStr := strings.TrimPrefix(header, "Bearer ")
		claims := &Claims{}
		_, err := jwt.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (interface{}, error) {
			return []byte(config.Global.JWT.Secret), nil
		})
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, models.Fail(401, "invalid token"))
			return
		}
		c.Set("user_id", claims.UserID)
		c.Next()
	}
}

func CurrentUserID(c *gin.Context) uint {
	id, _ := c.Get("user_id")
	v, _ := id.(uint)
	return v
}
