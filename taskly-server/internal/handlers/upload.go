package handlers

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"taskly-server/internal/models"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type UploadHandler struct{}

func NewUploadHandler() *UploadHandler { return &UploadHandler{} }

// UploadDir is where uploaded images are persisted; routes.Setup serves it at
// /uploads. Override via UPLOAD_DIR (systemd sets an absolute path — the
// service's cwd is not the app dir).
func UploadDir() string {
	if dir := os.Getenv("UPLOAD_DIR"); dir != "" {
		return dir
	}
	return "./uploads"
}

// PublicBaseURL is the externally reachable origin used to build file URLs.
func PublicBaseURL() string {
	if base := os.Getenv("PUBLIC_BASE_URL"); base != "" {
		return strings.TrimRight(base, "/")
	}
	return "https://taskly.cnirv.com"
}

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

	data, err := io.ReadAll(io.LimitReader(file, 10<<20)) // 10MB limit
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.Fail(500, "read error"))
		return
	}

	ext := filepath.Ext(header.Filename)
	if ext == "" {
		ext = ".jpg"
	}
	filename := uuid.New().String() + ext

	// Persist to local disk; the file is served back at /uploads/<name>.
	// (Move to OSS/S3 when traffic outgrows one box.)
	dir := UploadDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		c.JSON(http.StatusInternalServerError, models.Fail(500, "storage error"))
		return
	}
	if err := os.WriteFile(filepath.Join(dir, filename), data, 0o644); err != nil {
		c.JSON(http.StatusInternalServerError, models.Fail(500, "storage error"))
		return
	}

	url := fmt.Sprintf("%s/uploads/%s", PublicBaseURL(), filename)
	c.JSON(http.StatusOK, models.OK(gin.H{"url": url}))
}
