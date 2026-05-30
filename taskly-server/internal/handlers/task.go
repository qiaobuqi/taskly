package handlers

import (
	"net/http"
	"strconv"

	"taskly-server/internal/database"
	"taskly-server/internal/middleware"
	"taskly-server/internal/models"

	"github.com/gin-gonic/gin"
)

type TaskHandler struct{}

func NewTaskHandler() *TaskHandler { return &TaskHandler{} }

// GET /v1/tasks
func (h *TaskHandler) List(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	size, _ := strconv.Atoi(c.DefaultQuery("size", "20"))
	category := c.Query("category")
	sort := c.DefaultQuery("sort", "newest")

	q := database.DB.Model(&models.Task{}).Where("status = 'open'").
		Preload("Publisher")
	if category != "" {
		q = q.Where("category = ?", category)
	}
	switch sort {
	case "price_low":
		q = q.Order("budget asc")
	case "price_high":
		q = q.Order("budget desc")
	default:
		q = q.Order("created_at desc")
	}

	var total int64
	q.Count(&total)

	var tasks []models.Task
	q.Offset((page - 1) * size).Limit(size).Find(&tasks)

	// Populate applicant counts
	for i := range tasks {
		var cnt int64
		database.DB.Model(&models.Application{}).Where("task_id = ?", tasks[i].ID).Count(&cnt)
		tasks[i].ApplicantCount = int(cnt)
	}

	c.JSON(http.StatusOK, models.Page(tasks, total, page, size))
}

// GET /v1/tasks/:id
func (h *TaskHandler) Get(c *gin.Context) {
	var task models.Task
	if err := database.DB.Preload("Publisher").Preload("Assignee").
		First(&task, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, models.Fail(404, "task not found"))
		return
	}
	var cnt int64
	database.DB.Model(&models.Application{}).Where("task_id = ?", task.ID).Count(&cnt)
	task.ApplicantCount = int(cnt)
	c.JSON(http.StatusOK, models.OK(task))
}

// POST /v1/tasks
func (h *TaskHandler) Create(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var req struct {
		Title       string   `json:"title" binding:"required"`
		Description string   `json:"description"`
		Category    string   `json:"category" binding:"required"`
		Budget      float64  `json:"budget" binding:"required,gt=0"`
		Currency    string   `json:"currency"`
		Address     string   `json:"address" binding:"required"`
		Latitude    *float64 `json:"latitude"`
		Longitude   *float64 `json:"longitude"`
		Deadline    *string  `json:"deadline"`
		Images      []string `json:"images"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}
	if req.Currency == "" {
		req.Currency = "USD"
	}
	task := models.Task{
		Title:       req.Title,
		Description: req.Description,
		Category:    req.Category,
		Budget:      req.Budget,
		Currency:    req.Currency,
		Address:     req.Address,
		Latitude:    req.Latitude,
		Longitude:   req.Longitude,
		PublisherID: uid,
		Status:      "open",
		Images:      req.Images,
	}
	if req.Images == nil {
		task.Images = []string{}
	}
	database.DB.Create(&task)
	database.DB.Preload("Publisher").First(&task, task.ID)
	c.JSON(http.StatusOK, models.OK(task))
}

// GET /v1/tasks/:id/applications
func (h *TaskHandler) GetApplications(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	taskID := c.Param("id")

	var task models.Task
	if database.DB.First(&task, taskID).Error != nil {
		c.JSON(http.StatusNotFound, models.Fail(404, "task not found"))
		return
	}
	if task.PublisherID != uid {
		c.JSON(http.StatusForbidden, models.Fail(403, "forbidden"))
		return
	}

	var apps []models.Application
	database.DB.Where("task_id = ?", taskID).Preload("Applicant").Find(&apps)
	c.JSON(http.StatusOK, models.OK(apps))
}

// POST /v1/tasks/:id/apply
func (h *TaskHandler) Apply(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	taskID := c.Param("id")

	// Must be verified to apply
	var user models.User
	database.DB.First(&user, uid)
	if user.VerificationStatus != "approved" {
		c.JSON(http.StatusForbidden, models.Fail(403, "identity verification required to apply"))
		return
	}

	var task models.Task
	if database.DB.First(&task, taskID).Error != nil {
		c.JSON(http.StatusNotFound, models.Fail(404, "task not found"))
		return
	}
	if task.PublisherID == uid {
		c.JSON(http.StatusBadRequest, models.Fail(400, "cannot apply to your own task"))
		return
	}

	var req struct {
		Message       string  `json:"message" binding:"required"`
		ProposedPrice float64 `json:"proposed_price" binding:"required,gt=0"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}

	// Prevent duplicate application
	var count int64
	database.DB.Model(&models.Application{}).
		Where("task_id = ? AND applicant_id = ?", taskID, uid).Count(&count)
	if count > 0 {
		c.JSON(http.StatusConflict, models.Fail(409, "already applied"))
		return
	}

	app := models.Application{
		TaskID:        task.ID,
		ApplicantID:   uid,
		Message:       req.Message,
		ProposedPrice: req.ProposedPrice,
		Status:        "pending",
	}
	database.DB.Create(&app)
	c.JSON(http.StatusOK, models.OK(app))
}

// POST /v1/tasks/:id/applications/:appId/accept
func (h *TaskHandler) AcceptApplication(c *gin.Context) {
	uid := middleware.CurrentUserID(c)

	var task models.Task
	if database.DB.First(&task, c.Param("id")).Error != nil {
		c.JSON(http.StatusNotFound, models.Fail(404, "task not found"))
		return
	}
	if task.PublisherID != uid {
		c.JSON(http.StatusForbidden, models.Fail(403, "forbidden"))
		return
	}

	var app models.Application
	if database.DB.First(&app, c.Param("appId")).Error != nil {
		c.JSON(http.StatusNotFound, models.Fail(404, "application not found"))
		return
	}

	// Accept this, reject others
	database.DB.Model(&models.Application{}).
		Where("task_id = ? AND id != ?", task.ID, app.ID).
		Update("status", "rejected")
	database.DB.Model(&app).Update("status", "accepted")

	// Move task to in_progress, set assignee
	database.DB.Model(&task).Updates(map[string]interface{}{
		"status":      "in_progress",
		"assignee_id": app.ApplicantID,
	})

	c.JSON(http.StatusOK, models.OK(gin.H{"message": "application accepted"}))
}

// POST /v1/tasks/:id/complete  (assignee marks complete)
func (h *TaskHandler) MarkComplete(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var req struct {
		Note             string   `json:"note"`
		CompletionImages []string `json:"completion_images"`
	}
	c.ShouldBindJSON(&req)

	var task models.Task
	if database.DB.First(&task, c.Param("id")).Error != nil {
		c.JSON(http.StatusNotFound, models.Fail(404, "task not found"))
		return
	}
	if task.AssigneeID == nil || *task.AssigneeID != uid {
		c.JSON(http.StatusForbidden, models.Fail(403, "forbidden"))
		return
	}

	database.DB.Model(&task).Update("status", "pending_confirm")
	c.JSON(http.StatusOK, models.OK(gin.H{"message": "completion submitted"}))
}

// POST /v1/tasks/:id/confirm  (publisher confirms, triggers payment release)
func (h *TaskHandler) ConfirmCompletion(c *gin.Context) {
	uid := middleware.CurrentUserID(c)

	var task models.Task
	if database.DB.First(&task, c.Param("id")).Error != nil {
		c.JSON(http.StatusNotFound, models.Fail(404, "task not found"))
		return
	}
	if task.PublisherID != uid {
		c.JSON(http.StatusForbidden, models.Fail(403, "forbidden"))
		return
	}
	if task.Status != "pending_confirm" {
		c.JSON(http.StatusBadRequest, models.Fail(400, "task is not pending confirmation"))
		return
	}

	database.DB.Model(&task).Update("status", "completed")
	releasePayment(task.ID)
	c.JSON(http.StatusOK, models.OK(gin.H{"message": "task completed, payment released"}))
}
