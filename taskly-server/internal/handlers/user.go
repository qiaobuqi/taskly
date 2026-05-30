package handlers

import (
	"net/http"

	"taskly-server/internal/database"
	"taskly-server/internal/middleware"
	"taskly-server/internal/models"

	"github.com/gin-gonic/gin"
)

type UserHandler struct{}

func NewUserHandler() *UserHandler { return &UserHandler{} }

// GET /v1/users/me
func (h *UserHandler) GetMe(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var user models.User
	if err := database.DB.First(&user, uid).Error; err != nil {
		c.JSON(http.StatusNotFound, models.Fail(404, "user not found"))
		return
	}
	c.JSON(http.StatusOK, models.OK(user))
}

// PUT /v1/users/me
func (h *UserHandler) UpdateMe(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var req struct {
		Nickname  string   `json:"nickname"`
		Bio       string   `json:"bio"`
		SkillTags []string `json:"skill_tags"`
		Avatar    string   `json:"avatar"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}
	updates := map[string]interface{}{}
	if req.Nickname != "" {
		updates["nickname"] = req.Nickname
	}
	if req.Bio != "" {
		updates["bio"] = req.Bio
	}
	if req.Avatar != "" {
		updates["avatar"] = req.Avatar
	}
	if req.SkillTags != nil {
		updates["skill_tags"] = req.SkillTags
	}
	database.DB.Model(&models.User{}).Where("id = ?", uid).Updates(updates)

	var user models.User
	database.DB.First(&user, uid)
	c.JSON(http.StatusOK, models.OK(user))
}

// GET /v1/users/me/tasks
func (h *UserHandler) GetMyTasks(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var tasks []models.Task
	database.DB.Where("publisher_id = ?", uid).
		Preload("Publisher").Preload("Assignee").
		Order("created_at desc").Find(&tasks)
	c.JSON(http.StatusOK, models.OK(tasks))
}

// GET /v1/users/me/jobs
func (h *UserHandler) GetMyJobs(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var tasks []models.Task
	database.DB.Where("assignee_id = ?", uid).
		Preload("Publisher").Preload("Assignee").
		Order("created_at desc").Find(&tasks)
	c.JSON(http.StatusOK, models.OK(tasks))
}

// GET /v1/users/me/verification
func (h *UserHandler) GetVerification(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var v models.Verification
	if err := database.DB.Where("user_id = ?", uid).First(&v).Error; err != nil {
		c.JSON(http.StatusOK, models.OK(gin.H{"status": "none"}))
		return
	}
	c.JSON(http.StatusOK, models.OK(v))
}

// POST /v1/users/me/verification
func (h *UserHandler) SubmitVerification(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var req struct {
		RealName      string `json:"real_name" binding:"required"`
		DocumentType  string `json:"document_type" binding:"required"`
		FrontImageURL string `json:"front_image_url" binding:"required"`
		BackImageURL  string `json:"back_image_url"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}

	v := models.Verification{
		UserID:        uid,
		RealName:      req.RealName,
		DocumentType:  req.DocumentType,
		FrontImageURL: req.FrontImageURL,
		BackImageURL:  req.BackImageURL,
		Status:        "pending",
	}
	database.DB.Where("user_id = ?", uid).Assign(v).FirstOrCreate(&v)
	// Update user verification status
	database.DB.Model(&models.User{}).Where("id = ?", uid).Update("verification_status", "pending")

	c.JSON(http.StatusOK, models.OK(v))
}

// GET /v1/users/:id
func (h *UserHandler) GetUser(c *gin.Context) {
	var user models.User
	if err := database.DB.First(&user, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, models.Fail(404, "user not found"))
		return
	}
	// Clear sensitive fields
	user.Email = ""
	c.JSON(http.StatusOK, models.OK(user))
}

// GET /v1/wallet
func (h *UserHandler) GetWallet(c *gin.Context) {
	uid := middleware.CurrentUserID(c)

	var balance, escrowed float64
	database.DB.Model(&models.WalletTransaction{}).
		Where("user_id = ? AND type IN ('release','refund')", uid).
		Select("COALESCE(SUM(amount), 0)").Scan(&balance)
	database.DB.Model(&models.WalletTransaction{}).
		Where("user_id = ? AND type = 'payment'", uid).
		Select("COALESCE(SUM(amount), 0)").Scan(&escrowed)

	// Subtract withdrawals from balance
	var withdrawn float64
	database.DB.Model(&models.WalletTransaction{}).
		Where("user_id = ? AND type = 'withdrawal'", uid).
		Select("COALESCE(SUM(amount), 0)").Scan(&withdrawn)
	balance -= withdrawn

	var txs []models.WalletTransaction
	database.DB.Where("user_id = ?", uid).Order("created_at desc").Limit(50).Find(&txs)

	c.JSON(http.StatusOK, models.OK(gin.H{
		"balance":         balance,
		"escrowed_amount": escrowed,
		"currency":        "USD",
		"transactions":    txs,
	}))
}

// POST /v1/wallet/withdraw
func (h *UserHandler) Withdraw(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var req struct {
		Amount      float64 `json:"amount" binding:"required,gt=0"`
		Currency    string  `json:"currency"`
		AccountInfo string  `json:"account_info" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}
	if req.Currency == "" {
		req.Currency = "USD"
	}
	tx := models.WalletTransaction{
		UserID:      uid,
		Type:        "withdrawal",
		Amount:      req.Amount,
		Currency:    req.Currency,
		Description: "Withdrawal to: " + req.AccountInfo,
	}
	database.DB.Create(&tx)
	c.JSON(http.StatusOK, models.OK(gin.H{"message": "withdrawal requested"}))
}
