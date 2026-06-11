package handlers

import (
	"net/http"
	"strconv"
	"sync"

	"taskly-server/internal/database"
	"taskly-server/internal/middleware"
	"taskly-server/internal/models"

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

		// Push to receiver if online
		h.mu.RLock()
		receiverConn, online := h.clients[msg.ReceiverID]
		h.mu.RUnlock()
		if online {
			receiverConn.WriteJSON(saved)
		}
	}
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

	var users []models.User
	for _, row := range rows {
		if _, isBlocked := blocked[row.OtherID]; isBlocked {
			continue
		}
		var u models.User
		if database.DB.First(&u, row.OtherID).Error == nil {
			users = append(users, u)
		}
	}
	if users == nil {
		users = []models.User{}
	}
	c.JSON(http.StatusOK, models.OK(users))
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
		Content    string `json:"content" binding:"required"`
		TaskID     *uint  `json:"task_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}
	// Filter objectionable content in chat (App Store Guideline 1.2).
	if ContainsObjectionableContent(req.Content) {
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
