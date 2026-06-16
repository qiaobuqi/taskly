package handlers

import (
	"net/http"
	"sort"
	"strconv"
	"sync"
	"time"

	"taskly-server/internal/database"
	"taskly-server/internal/middleware"
	"taskly-server/internal/models"
	"taskly-server/internal/services"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

type MessageHandler struct {
	mu      sync.RWMutex
	clients map[uint]*websocket.Conn // userID -> conn
}

func NewMessageHandler() *MessageHandler {
	return &MessageHandler{clients: make(map[uint]*websocket.Conn)}
}

var wsUpgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin:     func(r *http.Request) bool { return true },
}

// GET /v1/messages/ws  (WebSocket upgrade)
func (h *MessageHandler) WebSocket(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	conn, err := wsUpgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}
	defer conn.Close()

	h.mu.Lock()
	h.clients[uid] = conn
	h.mu.Unlock()
	defer func() {
		h.mu.Lock()
		delete(h.clients, uid)
		h.mu.Unlock()
	}()

	for {
		var msg struct {
			ReceiverID uint   `json:"receiver_id"`
			Content    string `json:"content"`
			TaskID     *uint  `json:"task_id"`
		}
		if err := conn.ReadJSON(&msg); err != nil {
			break
		}
		saved := models.Message{
			SenderID:   uid,
			ReceiverID: msg.ReceiverID,
			TaskID:     msg.TaskID,
			Content:    msg.Content,
		}
		database.DB.Create(&saved)

		// Push to receiver if online; otherwise send an APNs push.
		h.mu.RLock()
		receiverConn, online := h.clients[msg.ReceiverID]
		h.mu.RUnlock()
		if online {
			receiverConn.WriteJSON(saved)
		} else {
			var sender models.User
			database.DB.Select("nickname").First(&sender, uid)
			services.PushNewMessage(&saved, sender.Nickname)
		}
	}
}

// ConversationDTO is one row in the Messages tab: who you're talking to, the
// most recent message (for the preview line) and how many of theirs you haven't
// read. Returning this richly so the list looks like a real inbox instead of a
// column of bare names (which read as "empty/unfinished" to App Review).
type ConversationDTO struct {
	OtherUser   models.User     `json:"other_user"`
	LastMessage *models.Message `json:"last_message"`
	UnreadCount int64           `json:"unread_count"`
}

// GET /v1/messages/conversations
func (h *MessageHandler) GetConversations(c *gin.Context) {
	uid := middleware.CurrentUserID(c)

	// Get distinct users this user has chatted with
	type Row struct {
		OtherID uint
	}
	var rows []Row
	database.DB.Raw(`
		SELECT DISTINCT
			CASE WHEN sender_id = ? THEN receiver_id ELSE sender_id END AS other_id
		FROM messages
		WHERE (sender_id = ? OR receiver_id = ?)
		  AND deleted_at IS NULL
	`, uid, uid, uid).Scan(&rows)

	// Hide conversations with blocked users from the list instantly (Guideline 1.2).
	blocked := make(map[uint]struct{})
	for _, id := range BlockedUserIDs(uid) {
		blocked[id] = struct{}{}
	}

	convos := []ConversationDTO{}
	for _, row := range rows {
		if _, isBlocked := blocked[row.OtherID]; isBlocked {
			continue
		}
		var u models.User
		if database.DB.First(&u, row.OtherID).Error != nil {
			continue
		}

		var last models.Message
		hasLast := database.DB.Where(
			"(sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)",
			uid, row.OtherID, row.OtherID, uid,
		).Order("created_at desc").First(&last).Error == nil

		var unread int64
		database.DB.Model(&models.Message{}).
			Where("sender_id = ? AND receiver_id = ? AND is_read = false", row.OtherID, uid).
			Count(&unread)

		dto := ConversationDTO{OtherUser: u, UnreadCount: unread}
		if hasLast {
			dto.LastMessage = &last
		}
		convos = append(convos, dto)
	}

	// Most recent conversation first (empty/no-message threads sink to the bottom).
	sort.SliceStable(convos, func(i, j int) bool {
		ti, tj := time.Time{}, time.Time{}
		if convos[i].LastMessage != nil {
			ti = convos[i].LastMessage.CreatedAt
		}
		if convos[j].LastMessage != nil {
			tj = convos[j].LastMessage.CreatedAt
		}
		return ti.After(tj)
	})

	c.JSON(http.StatusOK, models.OK(convos))
}

// GET /v1/messages/:userId
func (h *MessageHandler) GetMessages(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	otherID, _ := strconv.Atoi(c.Param("userId"))

	var msgs []models.Message
	database.DB.Where(
		"(sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)",
		uid, otherID, otherID, uid,
	).Order("created_at asc").Limit(100).Find(&msgs)

	// Mark received messages as read
	database.DB.Model(&models.Message{}).
		Where("sender_id = ? AND receiver_id = ? AND is_read = false", otherID, uid).
		Update("is_read", true)

	if msgs == nil {
		msgs = []models.Message{}
	}
	c.JSON(http.StatusOK, models.OK(msgs))
}

// POST /v1/messages  (REST fallback for non-WS clients)
func (h *MessageHandler) Send(c *gin.Context) {
	uid := middleware.CurrentUserID(c)
	var req struct {
		ReceiverID uint   `json:"receiver_id" binding:"required"`
		Content    string `json:"content"`
		ImageURL   string `json:"image_url"`
		TaskID     *uint  `json:"task_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}
	// A message is text, an image, or both — but never empty.
	if req.Content == "" && req.ImageURL == "" {
		c.JSON(http.StatusBadRequest, models.Fail(400, "message must contain text or an image"))
		return
	}
	// Filter objectionable content in chat (App Store Guideline 1.2).
	if req.Content != "" && ContainsObjectionableContent(req.Content) {
		c.JSON(http.StatusBadRequest, models.Fail(400, "Your message contains language that violates our content policy."))
		return
	}
	// Don't deliver messages to/from a blocked user.
	for _, id := range BlockedUserIDs(uid) {
		if id == req.ReceiverID {
			c.JSON(http.StatusForbidden, models.Fail(403, "You can no longer message this user."))
			return
		}
	}
	msg := models.Message{
		SenderID:   uid,
		ReceiverID: req.ReceiverID,
		Content:    req.Content,
		ImageURL:   req.ImageURL,
		TaskID:     req.TaskID,
	}
	database.DB.Create(&msg)

	// Push to receiver if online
	h.mu.RLock()
	conn, online := h.clients[req.ReceiverID]
	h.mu.RUnlock()
	if online {
		conn.WriteJSON(msg)
	}

	c.JSON(http.StatusOK, models.OK(msg))
}
