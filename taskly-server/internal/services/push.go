package services

import (
	"fmt"
	"log"

	"taskly-server/internal/config"
	"taskly-server/internal/database"
	"taskly-server/internal/models"

	"github.com/sideshow/apns2"
	"github.com/sideshow/apns2/payload"
	"github.com/sideshow/apns2/token"
)

// PushService 通过 APNs(.p8 Auth Key,token 方式)给 iOS 设备发推送。
// Taskly 复用与路遇同 Apple Team 的 APNs 密钥,topic 用 Taskly 自己的 Bundle ID。
type PushService struct {
	client   *apns2.Client
	bundleID string
}

// GlobalPush 全局实例;未初始化(未配置 APNs)时为 nil,调用方需判空。
var GlobalPush *PushService

// InitPush 从配置初始化推送服务。未启用或缺参时返回 nil error 但不创建实例,
// 这样推送只是静默跳过,绝不影响主流程。
func InitPush() error {
	cfg := config.Global.APNS
	if !cfg.Enabled {
		log.Println("📌 APNs 推送未启用(apns.enabled=false)")
		return nil
	}
	if cfg.CertPath == "" || cfg.KeyID == "" || cfg.TeamID == "" || cfg.BundleID == "" {
		log.Println("📌 APNs 配置不完整,推送功能跳过")
		return nil
	}
	authKey, err := token.AuthKeyFromFile(cfg.CertPath)
	if err != nil {
		return fmt.Errorf("load .p8 failed: %w", err)
	}
	client := apns2.NewTokenClient(&token.Token{AuthKey: authKey, KeyID: cfg.KeyID, TeamID: cfg.TeamID})
	if cfg.Sandbox {
		client = client.Development()
	} else {
		client = client.Production()
	}
	GlobalPush = &PushService{client: client, bundleID: cfg.BundleID}
	log.Printf("✓ APNs 推送已就绪 [%s] bundle=%s keyID=%s",
		map[bool]string{true: "沙盒", false: "生产"}[cfg.Sandbox], cfg.BundleID, cfg.KeyID)
	return nil
}

// SendToUser 给某用户发推送(校验开关与设备令牌)。data 会作为自定义字段带给客户端。
func (s *PushService) SendToUser(userID uint, title, body string, data map[string]interface{}) error {
	var u models.User
	if err := database.DB.First(&u, userID).Error; err != nil {
		return err
	}
	if !u.PushEnabled || u.DeviceToken == "" {
		return nil // 用户关了推送或没令牌,静默跳过
	}
	return s.sendRaw(u.DeviceToken, title, body, data)
}

func (s *PushService) sendRaw(deviceToken, title, body string, data map[string]interface{}) error {
	p := payload.NewPayload().AlertTitle(title).AlertBody(body).Sound("default").Badge(1)
	for k, v := range data {
		p.Custom(k, v)
	}
	res, err := s.client.Push(&apns2.Notification{
		DeviceToken: deviceToken,
		Topic:       s.bundleID,
		Payload:     p,
	})
	if err != nil {
		return err
	}
	if res.StatusCode != 200 {
		return fmt.Errorf("apns %d: %s", res.StatusCode, res.Reason)
	}
	return nil
}

// SendTest 给指定设备令牌发测试推送(用于自检)。
func (s *PushService) SendTest(deviceToken string) error {
	return s.sendRaw(deviceToken, "Taskly", "这是一条测试推送 ✅", map[string]interface{}{"type": "test"})
}

// PushNewMessage 收到新私信时给接收者发推送(离线/在线都发,客户端按需处理)。
// 任何失败只记日志,不阻断消息发送主流程。
func PushNewMessage(msg *models.Message, senderName string) {
	if GlobalPush == nil {
		return
	}
	body := senderName + " 给你发来一条消息"
	if msg.Content != "" {
		preview := msg.Content
		if len([]rune(preview)) > 50 {
			preview = string([]rune(preview)[:47]) + "..."
		}
		body = senderName + ": " + preview
	}
	data := map[string]interface{}{
		"type":       "message",
		"sender_id":  msg.SenderID,
		"message_id": msg.ID,
	}
	if msg.TaskID != nil {
		data["task_id"] = *msg.TaskID
	}
	if err := GlobalPush.SendToUser(msg.ReceiverID, "新消息", body, data); err != nil {
		log.Printf("📌 push message failed: %v", err)
	}
}
