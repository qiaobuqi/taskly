package handlers

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	"taskly-server/internal/database"
	"taskly-server/internal/models"
	"taskly-server/internal/utils"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

type AuthHandler struct{}

func NewAuthHandler() *AuthHandler { return &AuthHandler{} }

// POST /v1/auth/register
func (h *AuthHandler) Register(c *gin.Context) {
	var req struct {
		Email    string `json:"email" binding:"required,email"`
		Password string `json:"password" binding:"required,min=8"`
		Nickname string `json:"nickname" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}

	var count int64
	database.DB.Model(&models.User{}).Where("email = ?", req.Email).Count(&count)
	if count > 0 {
		c.JSON(http.StatusConflict, models.Fail(409, "email already registered"))
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.Fail(500, "server error"))
		return
	}

	user := models.User{
		Email:        req.Email,
		PasswordHash: string(hash),
		Nickname:     req.Nickname,
		SkillTags:    []string{},
	}
	if err := database.DB.Create(&user).Error; err != nil {
		c.JSON(http.StatusInternalServerError, models.Fail(500, "create user failed"))
		return
	}

	token, _ := utils.GenerateToken(user.ID)
	c.JSON(http.StatusOK, models.OK(gin.H{"token": token, "user": user}))
}

// POST /v1/auth/login
func (h *AuthHandler) Login(c *gin.Context) {
	var req struct {
		Email    string `json:"email" binding:"required"`
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}

	var user models.User
	if err := database.DB.Where("email = ?", req.Email).First(&user).Error; err != nil {
		c.JSON(http.StatusUnauthorized, models.Fail(401, "invalid credentials"))
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)) != nil {
		c.JSON(http.StatusUnauthorized, models.Fail(401, "invalid credentials"))
		return
	}

	token, _ := utils.GenerateToken(user.ID)
	c.JSON(http.StatusOK, models.OK(gin.H{"token": token, "user": user}))
}

// POST /v1/auth/apple
func (h *AuthHandler) AppleLogin(c *gin.Context) {
	var req struct {
		IdentityToken string `json:"identity_token" binding:"required"`
		Email         string `json:"email"`
		FullName      string `json:"full_name"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}

	appleUserID, email, err := parseAppleToken(req.IdentityToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, models.Fail(401, "invalid apple token"))
		return
	}
	if email == "" {
		email = req.Email
	}

	var user models.User
	if database.DB.Where("apple_user_id = ?", appleUserID).First(&user).Error != nil {
		nickname := req.FullName
		if nickname == "" {
			suffix := appleUserID
			if len(suffix) > 6 {
				suffix = suffix[len(suffix)-6:]
			}
			nickname = "User" + suffix
		}
		user = models.User{
			AppleUserID: appleUserID,
			Email:       email,
			Nickname:    nickname,
			SkillTags:   []string{},
		}
		if err := database.DB.Create(&user).Error; err != nil {
			c.JSON(http.StatusInternalServerError, models.Fail(500, "create user failed"))
			return
		}
	}

	token, _ := utils.GenerateToken(user.ID)
	c.JSON(http.StatusOK, models.OK(gin.H{"token": token, "user": user}))
}

// parseAppleToken decodes the JWT payload to get sub and email.
// Production: use apple's public keys to fully verify the signature.
func parseAppleToken(identityToken string) (sub, email string, err error) {
	parts := strings.Split(identityToken, ".")
	if len(parts) != 3 {
		return "", "", fmt.Errorf("invalid jwt format")
	}
	payload := parts[1]
	// Add base64 padding
	switch len(payload) % 4 {
	case 2:
		payload += "=="
	case 3:
		payload += "="
	}
	decoded, err := base64.URLEncoding.DecodeString(payload)
	if err != nil {
		return "", "", err
	}
	var claims map[string]interface{}
	if err := json.Unmarshal(decoded, &claims); err != nil {
		return "", "", err
	}
	// Verify issuer
	if iss, _ := claims["iss"].(string); iss != "https://appleid.apple.com" {
		return "", "", fmt.Errorf("invalid issuer")
	}
	sub, _ = claims["sub"].(string)
	email, _ = claims["email"].(string)
	if sub == "" {
		return "", "", fmt.Errorf("missing sub claim")
	}
	return sub, email, nil
}

// fetchAppleKeys is kept for future full signature verification
func fetchAppleKeys() ([]json.RawMessage, error) {
	resp, err := http.Get("https://appleid.apple.com/auth/keys")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	var keys struct {
		Keys []json.RawMessage `json:"keys"`
	}
	json.Unmarshal(body, &keys)
	return keys.Keys, nil
}
