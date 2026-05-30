package utils

import (
	"time"

	"taskly-server/internal/config"
	"taskly-server/internal/middleware"

	"github.com/golang-jwt/jwt/v4"
)

func GenerateToken(userID uint) (string, error) {
	hours := time.Duration(config.Global.JWT.ExpireHours) * time.Hour
	claims := middleware.Claims{
		UserID: userID,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(hours)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(config.Global.JWT.Secret))
}
