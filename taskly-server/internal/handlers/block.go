package handlers

import (
	"net/http"
	"strconv"

	"taskly-server/internal/database"
	"taskly-server/internal/middleware"
	"taskly-server/internal/models"

	"github.com/gin-gonic/gin"
)

type BlockHandler struct{}

func NewBlockHandler() *BlockHandler { return &BlockHandler{} }

// POST /v1/blocks  — block an abusive user.
//
// App Store Guideline 1.2: blocking must (a) remove the blocked user's content
// from the blocker's feed instantly — handled by BlockedUserIDs() in the task and
// message queries — and (b) notify the developer of the inappropriate content, so
// we also file a Report for moderation within 24h.
func (h *BlockHandler) Create(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var req struct {
		BlockedID uint   `json:"blocked_id" binding:"required"`
		Reason    string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}
	if req.BlockedID == uid {
		c.JSON(http.StatusBadRequest, models.Fail(400, "you cannot block yourself"))
		return
	}

	// Idempotent: ignore a duplicate block of the same user.
	block := models.Block{BlockerID: uid, BlockedID: req.BlockedID}
	database.DB.Where(models.Block{BlockerID: uid, BlockedID: req.BlockedID}).
		FirstOrCreate(&block)

	// Notify the developer of the objectionable user for 24h moderation.
	reason := req.Reason
	if reason == "" {
		reason = "user blocked as abusive"
	}
	database.DB.Create(&models.Report{
		ReporterID: uid,
		TargetType: "user",
		TargetID:   req.BlockedID,
		Reason:     reason,
		Status:     "pending",
	})

	c.JSON(http.StatusOK, models.OK(gin.H{"message": "user blocked"}))
}

// GET /v1/blocks  — list users the current user has blocked.
func (h *BlockHandler) List(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var blocks []models.Block
	database.DB.Where("blocker_id = ?", uid).Find(&blocks)
	ids := make([]uint, 0, len(blocks))
	for _, b := range blocks {
		ids = append(ids, b.BlockedID)
	}
	c.JSON(http.StatusOK, models.OK(gin.H{"blocked_ids": ids}))
}

// DELETE /v1/blocks/:userId  — unblock a previously blocked user.
func (h *BlockHandler) Delete(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	otherID, _ := strconv.Atoi(c.Param("userId"))
	database.DB.Where("blocker_id = ? AND blocked_id = ?", uid, otherID).
		Delete(&models.Block{})
	c.JSON(http.StatusOK, models.OK(gin.H{"message": "user unblocked"}))
}

// BlockedUserIDs returns every user id in a block relationship with uid in EITHER
// direction, so a blocked user is hidden from the blocker's feed and vice-versa.
// Used by the task list and message queries to filter content instantly.
func BlockedUserIDs(uid uint) []uint {
	if uid == 0 {
		return nil
	}
	var blocks []models.Block
	database.DB.Where("blocker_id = ? OR blocked_id = ?", uid, uid).Find(&blocks)
	seen := make(map[uint]struct{})
	ids := make([]uint, 0, len(blocks))
	for _, b := range blocks {
		other := b.BlockedID
		if b.BlockedID == uid {
			other = b.BlockerID
		}
		if _, ok := seen[other]; !ok {
			seen[other] = struct{}{}
			ids = append(ids, other)
		}
	}
	return ids
}
