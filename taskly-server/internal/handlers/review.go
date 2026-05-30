package handlers

import (
	"net/http"

	"taskly-server/internal/database"
	"taskly-server/internal/middleware"
	"taskly-server/internal/models"

	"github.com/gin-gonic/gin"
)

type ReviewHandler struct{}

func NewReviewHandler() *ReviewHandler { return &ReviewHandler{} }

// POST /v1/reviews
func (h *ReviewHandler) Create(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var req struct {
		TaskID     uint     `json:"task_id" binding:"required"`
		RevieweeID uint     `json:"reviewee_id" binding:"required"`
		Rating     int      `json:"rating" binding:"required,min=1,max=5"`
		Comment    string   `json:"comment" binding:"required"`
		Images     []string `json:"images"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}

	// Verify task is completed
	var task models.Task
	if database.DB.First(&task, req.TaskID).Error != nil {
		c.JSON(http.StatusNotFound, models.Fail(404, "task not found"))
		return
	}
	if task.Status != "completed" {
		c.JSON(http.StatusBadRequest, models.Fail(400, "task not completed yet"))
		return
	}
	// Verify reviewer is publisher or assignee
	if task.PublisherID != uid && (task.AssigneeID == nil || *task.AssigneeID != uid) {
		c.JSON(http.StatusForbidden, models.Fail(403, "not a participant of this task"))
		return
	}

	// Prevent duplicate review
	var count int64
	database.DB.Model(&models.Review{}).
		Where("task_id = ? AND reviewer_id = ?", req.TaskID, uid).Count(&count)
	if count > 0 {
		c.JSON(http.StatusConflict, models.Fail(409, "already reviewed"))
		return
	}

	images := req.Images
	if images == nil {
		images = []string{}
	}
	review := models.Review{
		TaskID:     req.TaskID,
		ReviewerID: uid,
		RevieweeID: req.RevieweeID,
		Rating:     req.Rating,
		Comment:    req.Comment,
		Images:     images,
	}
	database.DB.Create(&review)

	// Recalculate reviewee average rating
	updateUserRating(req.RevieweeID)

	database.DB.Preload("Reviewer").First(&review, review.ID)
	c.JSON(http.StatusOK, models.OK(review))
}

// GET /v1/users/:id/reviews
func (h *ReviewHandler) GetUserReviews(c *gin.Context) {
	var reviews []models.Review
	database.DB.Where("reviewee_id = ?", c.Param("id")).
		Preload("Reviewer").Order("created_at desc").Limit(50).Find(&reviews)
	if reviews == nil {
		reviews = []models.Review{}
	}
	c.JSON(http.StatusOK, models.OK(reviews))
}

func updateUserRating(userID uint) {
	type Result struct{ Avg float64 }
	var r Result
	database.DB.Model(&models.Review{}).
		Select("COALESCE(AVG(rating), 0) as avg").
		Where("reviewee_id = ?", userID).Scan(&r)

	var cnt int64
	database.DB.Model(&models.Review{}).Where("reviewee_id = ?", userID).Count(&cnt)

	database.DB.Model(&models.User{}).Where("id = ?", userID).Updates(map[string]interface{}{
		"rating":          r.Avg,
		"completed_count": cnt,
	})
}
