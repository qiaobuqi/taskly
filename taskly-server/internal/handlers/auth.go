package handlers

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"strings"
	"time"

	"taskly-server/internal/database"
	"taskly-server/internal/models"
	"taskly-server/internal/services"
	"taskly-server/internal/utils"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// errHandled rolls a transaction back when the handler has already chosen the
// HTTP error to send — it never reaches the client.
var errHandled = errors.New("handled")

type AuthHandler struct{}

func NewAuthHandler() *AuthHandler { return &AuthHandler{} }

// POST /v1/auth/send-code — email a 6-digit registration code (rate-limited 60s/email).
func (h *AuthHandler) SendCode(c *gin.Context) {
	var req struct {
		Email string `json:"email" binding:"required,email"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))

	var existing int64
	database.DB.Model(&models.User{}).Where("email = ?", req.Email).Count(&existing)
	if existing > 0 {
		c.JSON(http.StatusConflict, models.Fail(409, "email already registered"))
		return
	}

	// 60-second resend cooldown.
	var prev models.EmailCode
	if database.DB.Where("email = ?", req.Email).First(&prev).Error == nil {
		if time.Since(prev.UpdatedAt) < 60*time.Second {
			c.JSON(http.StatusTooManyRequests, models.Fail(429, "please wait before requesting another code"))
			return
		}
	}

	code := genCode()
	rec := models.EmailCode{Email: req.Email, Code: code, ExpiresAt: time.Now().Add(5 * time.Minute), Attempts: 0}
	// Upsert: keep one row per email with the newest code.
	database.DB.Where("email = ?", req.Email).Assign(map[string]interface{}{
		"code": code, "expires_at": rec.ExpiresAt, "attempts": 0,
	}).FirstOrCreate(&rec)

	_ = services.SendVerificationCode(req.Email, code)
	c.JSON(http.StatusOK, models.OK(gin.H{"message": "code sent"}))
}

func genCode() string {
	n, _ := rand.Int(rand.Reader, big.NewInt(1000000))
	return fmt.Sprintf("%06d", n.Int64())
}

// POST /v1/auth/register
func (h *AuthHandler) Register(c *gin.Context) {
	var req struct {
		Email    string `json:"email" binding:"required,email"`
		Password string `json:"password" binding:"required,min=8"`
		Nickname string `json:"nickname" binding:"required"`
		Code     string `json:"code" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))

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

	// users.email has no unique index (soft-deleted emails must stay re-registrable,
	// and MySQL lacks partial indexes), so duplicate prevention is the Count check
	// below. To keep two concurrent registrations from both passing it, the whole
	// check-and-create runs in one transaction that locks this email's email_codes
	// row (unique per email) — the second request blocks on the lock, then sees the
	// first one's user row / consumed code and fails cleanly.
	status, msg := 0, ""
	txErr := database.DB.Transaction(func(tx *gorm.DB) error {
		var ec models.EmailCode
		if tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("email = ?", req.Email).First(&ec).Error != nil {
			status, msg = http.StatusBadRequest, "please request a verification code first"
			return errHandled
		}

		var count int64
		tx.Model(&models.User{}).Where("email = ?", req.Email).Count(&count)
		if count > 0 {
			status, msg = http.StatusConflict, "email already registered"
			return errHandled
		}

		// Verify the code: must be unexpired, under the attempt cap, and match.
		if time.Now().After(ec.ExpiresAt) {
			status, msg = http.StatusBadRequest, "verification code expired"
			return errHandled
		}
		if ec.Attempts >= 5 {
			status, msg = http.StatusBadRequest, "too many attempts, request a new code"
			return errHandled
		}
		if ec.Code != req.Code {
			tx.Model(&ec).Update("attempts", ec.Attempts+1)
			status, msg = http.StatusBadRequest, "invalid verification code"
			return nil // commit the attempts increment, respond with the error below
		}

		if err := tx.Create(&user).Error; err != nil {
			return err
		}
		return tx.Where("email = ?", req.Email).Delete(&models.EmailCode{}).Error // consume the code
	})
	if txErr != nil && txErr != errHandled {
		c.JSON(http.StatusInternalServerError, models.Fail(500, "create user failed"))
		return
	}
	if msg != "" {
		c.JSON(status, models.Fail(status, msg))
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
