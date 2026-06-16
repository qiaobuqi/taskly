package handlers

import (
	"net/http"

	"taskly-server/internal/database"
	"taskly-server/internal/middleware"
	"taskly-server/internal/models"
	"taskly-server/internal/services"

	"github.com/gin-gonic/gin"
)

type PushHandler struct{}

func NewPushHandler() *PushHandler { return &PushHandler{} }

// POST /v1/push/device-token — 客户端拿到 APNs 设备令牌后上报。
// 上报即视为用户已授权通知,顺带打开推送开关。
func (h *PushHandler) UpdateDeviceToken(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var req struct {
		DeviceToken string `json:"device_token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, "device_token is required"))
		return
	}
	if err := database.DB.Model(&models.User{}).Where("id = ?", uid).
		Updates(map[string]interface{}{"device_token": req.DeviceToken, "push_enabled": true}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, models.Fail(500, "failed to save device token"))
		return
	}
	c.JSON(http.StatusOK, models.OK(gin.H{"updated": true}))
}

// GET /v1/push/settings — 返回推送开关与是否已有设备令牌(不返回令牌本身)。
func (h *PushHandler) GetSettings(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var u models.User
	if err := database.DB.First(&u, uid).Error; err != nil {
		c.JSON(http.StatusInternalServerError, models.Fail(500, "user not found"))
		return
	}
	c.JSON(http.StatusOK, models.OK(gin.H{
		"push_enabled": u.PushEnabled,
		"device_token": u.DeviceToken != "",
	}))
}

// PUT /v1/push/settings — 开/关推送。
func (h *PushHandler) UpdateSettings(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var req struct {
		Enabled bool `json:"enabled"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, "invalid body"))
		return
	}
	if err := database.DB.Model(&models.User{}).Where("id = ?", uid).
		Update("push_enabled", req.Enabled).Error; err != nil {
		c.JSON(http.StatusInternalServerError, models.Fail(500, "failed to update settings"))
		return
	}
	c.JSON(http.StatusOK, models.OK(gin.H{"push_enabled": req.Enabled}))
}

// POST /v1/push/test — 给自己发一条测试推送。
func (h *PushHandler) Test(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	if services.GlobalPush == nil {
		c.JSON(http.StatusServiceUnavailable, models.Fail(503, "push service not configured"))
		return
	}
	var u models.User
	if err := database.DB.First(&u, uid).Error; err != nil {
		c.JSON(http.StatusInternalServerError, models.Fail(500, "user not found"))
		return
	}
	if u.DeviceToken == "" {
		c.JSON(http.StatusBadRequest, models.Fail(400, "no device token registered"))
		return
	}
	if err := services.GlobalPush.SendTest(u.DeviceToken); err != nil {
		c.JSON(http.StatusInternalServerError, models.Fail(500, "push failed: "+err.Error()))
		return
	}
	c.JSON(http.StatusOK, models.OK(gin.H{"sent": true}))
}
