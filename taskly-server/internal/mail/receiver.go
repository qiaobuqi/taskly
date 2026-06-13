package mail

import (
	"io"
	"log"
	"strings"
	"time"

	"github.com/emersion/go-smtp"
)

// StartReceiver 启动入站收信服务(MTA),监听 25 端口,接收外部服务器投递给
// 本域(@MailDomain)的邮件,落地到 Maildir。以 goroutine 方式从 main 启动,
// 失败只记日志、不影响 Taskly 主服务。
func StartReceiver() {
	if !Cfg.Enabled {
		return
	}
	be := &recvBackend{}
	s := smtp.NewServer(be)
	s.Addr = Cfg.ReceiveAddr
	s.Domain = Cfg.Hostname
	s.ReadTimeout = 60 * time.Second
	s.WriteTimeout = 60 * time.Second
	s.MaxMessageBytes = Cfg.MaxMessageBytes
	s.MaxRecipients = 50
	s.AllowInsecureAuth = true // 入站 MTA 不认证

	log.Printf("📬 mail receiver listening on %s (domain @%s) -> %s", Cfg.ReceiveAddr, Cfg.MailDomain, Cfg.MaildirRoot)
	if err := s.ListenAndServe(); err != nil {
		log.Printf("📬 mail receiver stopped: %v", err)
	}
}

type recvBackend struct{}

func (b *recvBackend) NewSession(c *smtp.Conn) (smtp.Session, error) {
	return &recvSession{remote: c.Conn().RemoteAddr().String()}, nil
}

type recvSession struct {
	remote string
	from   string
	to     []string
}

func (s *recvSession) Mail(from string, _ *smtp.MailOptions) error {
	s.from = from
	return nil
}

func (s *recvSession) Rcpt(to string, _ *smtp.RcptOptions) error {
	// 只接收本域收件人,拒绝中继,避免成为开放中继被滥用
	if !strings.HasSuffix(strings.ToLower(to), "@"+Cfg.MailDomain) {
		log.Printf("📬 relay denied: %s (from %s)", to, s.remote)
		return &smtp.SMTPError{Code: 550, EnhancedCode: smtp.EnhancedCode{5, 7, 1}, Message: "Relay access denied"}
	}
	s.to = append(s.to, strings.ToLower(to))
	return nil
}

func (s *recvSession) Data(r io.Reader) error {
	raw, err := io.ReadAll(r)
	if err != nil {
		return err
	}
	for _, rcpt := range s.to {
		if err := DeliverMaildir(Cfg.MaildirRoot, rcpt, raw); err != nil {
			log.Printf("📬 deliver failed rcpt=%s: %v", rcpt, err)
			return &smtp.SMTPError{Code: 451, Message: "temporary storage failure"}
		}
		log.Printf("📬 received: to=%s from=%s size=%d", rcpt, s.from, len(raw))
	}
	return nil
}

func (s *recvSession) Reset()        { s.from = ""; s.to = nil }
func (s *recvSession) Logout() error { return nil }
