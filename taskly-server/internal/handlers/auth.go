package handlers

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"

	"taskly-server/internal/config"
	"taskly-server/internal/database"
	"taskly-server/internal/models"
	"taskly-server/internal/services"
	"taskly-server/internal/utils"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v4"
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
		Nonce         string `json:"nonce"` // raw nonce; client set request.nonce = sha256hex(nonce)
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}

	appleUserID, email, err := verifyAppleToken(req.IdentityToken, req.Nonce)
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

// verifyAppleToken fully validates an Apple identity token: it verifies the
// RS256 signature against Apple's published public keys, then checks the issuer,
// audience (must be our bundle id), expiry, and — when present — the nonce.
// A token that merely *looks* like Apple's (right iss claim, no valid signature)
// is rejected, closing the impersonation hole the old decode-only path left open.
func verifyAppleToken(identityToken, rawNonce string) (sub, email string, err error) {
	var claims jwt.MapClaims
	_, err = jwt.ParseWithClaims(identityToken, &claims, func(t *jwt.Token) (interface{}, error) {
		if t.Method.Alg() != "RS256" {
			return nil, fmt.Errorf("unexpected signing method: %s", t.Method.Alg())
		}
		kid, _ := t.Header["kid"].(string)
		if kid == "" {
			return nil, fmt.Errorf("missing kid")
		}
		return appleKeys.key(kid)
	})
	if err != nil {
		return "", "", err // covers bad signature and expired (exp validated by the lib)
	}

	if iss, _ := claims["iss"].(string); iss != "https://appleid.apple.com" {
		return "", "", fmt.Errorf("invalid issuer")
	}
	if !claims.VerifyAudience(config.Global.Apple.BundleID, true) {
		return "", "", fmt.Errorf("invalid audience")
	}
	// Replay protection: the client sets request.nonce = sha256hex(rawNonce), and
	// Apple echoes that hash into the token's `nonce` claim. Verify it when present.
	// Tokens from older app builds carry no nonce claim — those still pass (the
	// signature/aud checks above are the hard gate), so the server stays
	// backward-compatible while new builds get replay protection.
	if tokenNonce, ok := claims["nonce"].(string); ok && tokenNonce != "" {
		if rawNonce == "" {
			return "", "", fmt.Errorf("nonce required")
		}
		sum := sha256.Sum256([]byte(rawNonce))
		if hex.EncodeToString(sum[:]) != tokenNonce {
			return "", "", fmt.Errorf("nonce mismatch")
		}
	}

	sub, _ = claims["sub"].(string)
	email, _ = claims["email"].(string)
	if sub == "" {
		return "", "", fmt.Errorf("missing sub claim")
	}
	return sub, email, nil
}

// appleKeyStore caches Apple's JWKS (https://appleid.apple.com/auth/keys),
// refetching on a key-id miss (Apple rotates keys) or once the TTL lapses.
type appleKeyStore struct {
	mu        sync.RWMutex
	keys      map[string]*rsa.PublicKey
	fetchedAt time.Time
}

var appleKeys = &appleKeyStore{keys: map[string]*rsa.PublicKey{}}

const appleKeysTTL = time.Hour

func (s *appleKeyStore) key(kid string) (*rsa.PublicKey, error) {
	s.mu.RLock()
	k, ok := s.keys[kid]
	fresh := time.Since(s.fetchedAt) < appleKeysTTL
	s.mu.RUnlock()
	if ok && fresh {
		return k, nil
	}
	if err := s.refresh(); err != nil {
		// Serve a stale-but-cached key rather than failing logins on a transient
		// fetch error.
		if ok {
			return k, nil
		}
		return nil, err
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	if k, ok := s.keys[kid]; ok {
		return k, nil
	}
	return nil, fmt.Errorf("unknown apple key id: %s", kid)
}

func (s *appleKeyStore) refresh() error {
	resp, err := http.Get("https://appleid.apple.com/auth/keys")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	var jwks struct {
		Keys []struct {
			Kid string `json:"kid"`
			N   string `json:"n"`
			E   string `json:"e"`
		} `json:"keys"`
	}
	if err := json.Unmarshal(body, &jwks); err != nil {
		return err
	}
	parsed := map[string]*rsa.PublicKey{}
	for _, k := range jwks.Keys {
		nBytes, err := base64.RawURLEncoding.DecodeString(k.N)
		if err != nil {
			continue
		}
		eBytes, err := base64.RawURLEncoding.DecodeString(k.E)
		if err != nil {
			continue
		}
		parsed[k.Kid] = &rsa.PublicKey{
			N: new(big.Int).SetBytes(nBytes),
			E: int(new(big.Int).SetBytes(eBytes).Int64()),
		}
	}
	if len(parsed) == 0 {
		return fmt.Errorf("apple jwks empty")
	}
	s.mu.Lock()
	s.keys = parsed
	s.fetchedAt = time.Now()
	s.mu.Unlock()
	return nil
}
