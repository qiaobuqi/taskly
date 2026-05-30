package handlers

import (
	"net/http"

	"taskly-server/internal/database"
	"taskly-server/internal/middleware"
	"taskly-server/internal/models"

	"github.com/gin-gonic/gin"
)

type ReportHandler struct{}

func NewReportHandler() *ReportHandler { return &ReportHandler{} }

// POST /v1/reports
func (h *ReportHandler) Create(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var req struct {
		TargetType string `json:"target_type" binding:"required,oneof=task user message"`
		TargetID   uint   `json:"target_id" binding:"required"`
		Reason     string `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}

	report := models.Report{
		ReporterID: uid,
		TargetType: req.TargetType,
		TargetID:   req.TargetID,
		Reason:     req.Reason,
		Status:     "pending",
	}
	database.DB.Create(&report)
	c.JSON(http.StatusOK, models.OK(gin.H{"message": "report submitted"}))
}

// ── Admin routes ─────────────────────────────────────────────────────────────

// GET /v1/admin/verifications  (list pending verifications)
func AdminListVerifications(c *gin.Context) {
	var vs []models.Verification
	database.DB.Where("status = 'pending'").Order("created_at asc").Find(&vs)
	c.JSON(http.StatusOK, models.OK(vs))
}

// POST /v1/admin/verifications/:id/approve
func AdminApproveVerification(c *gin.Context) {
	var v models.Verification
	if database.DB.First(&v, c.Param("id")).Error != nil {
		c.JSON(http.StatusNotFound, models.Fail(404, "not found"))
		return
	}
	database.DB.Model(&v).Update("status", "approved")
	database.DB.Model(&models.User{}).Where("id = ?", v.UserID).Updates(map[string]interface{}{
		"verification_status": "approved",
		"is_verified":         true,
	})
	c.JSON(http.StatusOK, models.OK(gin.H{"message": "approved"}))
}

// POST /v1/admin/verifications/:id/reject
func AdminRejectVerification(c *gin.Context) {
	var req struct {
		Reason string `json:"reason"`
	}
	c.ShouldBindJSON(&req)

	var v models.Verification
	if database.DB.First(&v, c.Param("id")).Error != nil {
		c.JSON(http.StatusNotFound, models.Fail(404, "not found"))
		return
	}
	database.DB.Model(&v).Updates(map[string]interface{}{
		"status":           "rejected",
		"rejection_reason": req.Reason,
	})
	database.DB.Model(&models.User{}).Where("id = ?", v.UserID).
		Update("verification_status", "rejected")
	c.JSON(http.StatusOK, models.OK(gin.H{"message": "rejected"}))
}
