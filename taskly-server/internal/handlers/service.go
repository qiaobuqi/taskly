package handlers

import (
	"net/http"
	"strconv"

	"taskly-server/internal/database"
	"taskly-server/internal/middleware"
	"taskly-server/internal/models"

	"github.com/gin-gonic/gin"
)

type ServiceHandler struct{}

func NewServiceHandler() *ServiceHandler { return &ServiceHandler{} }

// GET /v1/services
func (h *ServiceHandler) List(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	size, _ := strconv.Atoi(c.DefaultQuery("size", "20"))
	category := c.Query("category")
	sort := c.DefaultQuery("sort", "newest")

	q := database.DB.Model(&models.ServiceCard{}).Where("is_active = true").Preload("Provider")
	if category != "" {
		q = q.Where("category = ?", category)
	}
	switch sort {
	case "price_low":
		q = q.Order("min_price asc")
	case "price_high":
		q = q.Order("min_price desc")
	default:
		q = q.Order("created_at desc")
	}

	var total int64
	q.Count(&total)
	var services []models.ServiceCard
	q.Offset((page - 1) * size).Limit(size).Find(&services)
	c.JSON(http.StatusOK, models.Page(services, total, page, size))
}

// POST /v1/services
func (h *ServiceHandler) Create(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var req struct {
		Title       string   `json:"title" binding:"required"`
		Description string   `json:"description"`
		Category    string   `json:"category" binding:"required"`
		MinPrice    float64  `json:"min_price" binding:"required,gt=0"`
		MaxPrice    float64  `json:"max_price" binding:"required,gt=0"`
		Currency    string   `json:"currency"`
		ServiceArea string   `json:"service_area" binding:"required"`
		SkillTags   []string `json:"skill_tags"`
		Images      []string `json:"images"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}
	if req.Currency == "" {
		req.Currency = "USD"
	}
	svc := models.ServiceCard{
		Title:       req.Title,
		Description: req.Description,
		Category:    req.Category,
		MinPrice:    req.MinPrice,
		MaxPrice:    req.MaxPrice,
		Currency:    req.Currency,
		ServiceArea: req.ServiceArea,
		SkillTags:   req.SkillTags,
		Images:      req.Images,
		ProviderID:  uid,
		IsActive:    true,
	}
	if svc.SkillTags == nil {
		svc.SkillTags = []string{}
	}
	if svc.Images == nil {
		svc.Images = []string{}
	}
	database.DB.Create(&svc)
	database.DB.Preload("Provider").First(&svc, svc.ID)
	c.JSON(http.StatusOK, models.OK(svc))
}

// DELETE /v1/services/:id
func (h *ServiceHandler) Delete(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var svc models.ServiceCard
	if database.DB.First(&svc, c.Param("id")).Error != nil {
		c.JSON(http.StatusNotFound, models.Fail(404, "service not found"))
		return
	}
	if svc.ProviderID != uid {
		c.JSON(http.StatusForbidden, models.Fail(403, "forbidden"))
		return
	}
	database.DB.Model(&svc).Update("is_active", false)
	c.JSON(http.StatusOK, models.OK(gin.H{"message": "deleted"}))
}
