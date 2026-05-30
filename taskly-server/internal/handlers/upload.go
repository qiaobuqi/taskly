package handlers

import (
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"strings"

	"taskly-server/internal/models"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type UploadHandler struct{}

func NewUploadHandler() *UploadHandler { return &UploadHandler{} }

// POST /v1/upload/image
func (h *UploadHandler) Image(c *gin.Context) {
	file, header, err := c.Request.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, "file required"))
		return
	}
	defer file.Close()

	contentType := header.Header.Get("Content-Type")
	if !strings.HasPrefix(contentType, "image/") {
		c.JSON(http.StatusBadRequest, models.Fail(400, "only images allowed"))
		return
	}

	// Read into memory (for MVP; production: upload to S3/Supabase Storage)
	data, err := io.ReadAll(io.LimitReader(file, 10<<20)) // 10MB limit
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.Fail(500, "read error"))
		return
	}
	_ = data // TODO: upload to cloud storage

	ext := filepath.Ext(header.Filename)
	if ext == "" {
		ext = ".jpg"
	}
	filename := uuid.New().String() + ext

	// MVP: return a placeholder URL (replace with actual CDN URL after upload)
	url := fmt.Sprintf("https://storage.taskly.app/images/%s", filename)
	c.JSON(http.StatusOK, models.OK(gin.H{"url": url}))
}
