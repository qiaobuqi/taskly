package middleware

import (
	"net/http"
	"strings"

	"taskly-server/internal/config"
	"taskly-server/internal/database"
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
		// Tokens outlive accounts (30-day expiry, no revocation list), so a token
		// for a deleted account must be rejected here, not just fail lookups later.
		var exists int64
		database.DB.Model(&models.User{}).Where("id = ?", claims.UserID).Count(&exists)
		if exists == 0 {
			c.AbortWithStatusJSON(http.StatusUnauthorized, models.Fail(401, "account no longer exists"))
			return
		}
		c.Set("user_id", claims.UserID)
		c.Next()
	}
}

// AdminRequired gates /v1/admin/*. Runs after AuthRequired; rejects unless the
// user row has is_admin set (flipped manually in the DB — there is no in-app
// path to admin, so the default is deny for every account).
func AdminRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		var user models.User
		if database.DB.First(&user, CurrentUserID(c)).Error != nil || !user.IsAdmin {
			c.AbortWithStatusJSON(http.StatusForbidden, models.Fail(403, "admin access required"))
			return
		}
		c.Next()
	}
}

// OptionalAuth sets user_id when a valid token is present but never rejects the
// request. Used by endpoints that work both logged-out and logged-in (e.g. the
// analytics ingest, which must capture app_open events before sign-in too).
func OptionalAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		if strings.HasPrefix(header, "Bearer ") {
			claims := &Claims{}
			if _, err := jwt.ParseWithClaims(strings.TrimPrefix(header, "Bearer "), claims,
				func(t *jwt.Token) (interface{}, error) {
					return []byte(config.Global.JWT.Secret), nil
				}); err == nil {
				c.Set("user_id", claims.UserID)
			}
		}
		c.Next()
	}
}

func CurrentUserID(c *gin.Context) uint {
	id, _ := c.Get("user_id")
	v, _ := id.(uint)
	return v
}
