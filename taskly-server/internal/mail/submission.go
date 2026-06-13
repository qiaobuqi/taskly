package mail

import (
	"bytes"
	"crypto/tls"
	"fmt"
	"io"
	"log"
	"net/smtp"
	"strings"
	"time"

	"taskly-server/internal/services"

	"github.com/emersion/go-message/mail"
	"github.com/emersion/go-sasl"
	gosmtp "github.com/emersion/go-smtp"
)

// StartSubmission 启动发信提交服务,供邮件客户端(网易/Outlook 等)登录后发信。
// 监听 :587(STARTTLS)和 :465(隐式 TLS)。认证通过后,把客户端提交的原始邮件
// 原样中继给阿里云 DirectMail SMTP 发出,保留完整 MIME(附件/抄送等)。
func StartSubmission() {
	if !Cfg.Enabled {
		return
	}
	cert, err := tls.LoadX509KeyPair(Cfg.TLSCert, Cfg.TLSKey)
	if err != nil {
		log.Printf("✉️  submission disabled: load TLS cert failed: %v", err)
		return
	}
	tlsConf := &tls.Config{Certificates: []tls.Certificate{cert}}

	newServer := func() *gosmtp.Server {
		s := gosmtp.NewServer(&subBackend{})
		s.Domain = Cfg.Hostname
		s.ReadTimeout = 60 * time.Second
		s.WriteTimeout = 60 * time.Second
		s.MaxMessageBytes = Cfg.MaxMessageBytes
		s.MaxRecipients = 100
		s.TLSConfig = tlsConf
		return s
	}

	// :465 隐式 TLS
	go func() {
		s := newServer()
		s.Addr = Cfg.SubmissionsAddr
		log.Printf("✉️  mail submission (implicit TLS) on %s", Cfg.SubmissionsAddr)
		if err := s.ListenAndServeTLS(); err != nil {
			log.Printf("✉️  submission(465) stopped: %v", err)
		}
	}()

	// :587 STARTTLS
	s := newServer()
	s.Addr = Cfg.SubmissionAddr
	log.Printf("✉️  mail submission (STARTTLS) on %s", Cfg.SubmissionAddr)
	if err := s.ListenAndServe(); err != nil {
		log.Printf("✉️  submission(587) stopped: %v", err)
	}
}

type subBackend struct{}

func (b *subBackend) NewSession(c *gosmtp.Conn) (gosmtp.Session, error) {
	return &subSession{}, nil
}

type subSession struct {
	authed bool
	user   string
	from   string
	to     []string
}

func (s *subSession) AuthMechanisms() []string {
	return []string{sasl.Plain, sasl.Login}
}

func (s *subSession) Auth(mech string) (sasl.Server, error) {
	check := func(username, password string) error {
		if !Authenticate(username, password) {
			return gosmtp.ErrAuthFailed
		}
		s.authed = true
		s.user = strings.ToLower(username)
		return nil
	}
	switch mech {
	case sasl.Plain:
		return sasl.NewPlainServer(func(identity, username, password string) error {
			return check(username, password)
		}), nil
	case sasl.Login:
		return &loginServer{check: check}, nil
	}
	return nil, gosmtp.ErrAuthUnsupported
}

// loginServer 实现 SASL LOGIN 机制的服务端(go-sasl 未内置)。
// 交互:服务端先要 Username,再要 Password,然后校验。
type loginServer struct {
	check func(username, password string) error
	user  string
	state int
}

func (l *loginServer) Next(resp []byte) (challenge []byte, done bool, err error) {
	switch l.state {
	case 0:
		l.state = 1
		return []byte("Username:"), false, nil
	case 1:
		l.user = string(resp)
		l.state = 2
		return []byte("Password:"), false, nil
	default:
		if err := l.check(l.user, string(resp)); err != nil {
			return nil, false, err
		}
		return nil, true, nil
	}
}

func (s *subSession) Mail(from string, _ *gosmtp.MailOptions) error {
	if !s.authed {
		return gosmtp.ErrAuthRequired
	}
	s.from = from
	return nil
}

func (s *subSession) Rcpt(to string, _ *gosmtp.RcptOptions) error {
	if !s.authed {
		return gosmtp.ErrAuthRequired
	}
	s.to = append(s.to, to)
	return nil
}

func (s *subSession) Data(r io.Reader) error {
	if !s.authed {
		return gosmtp.ErrAuthRequired
	}
	raw, err := io.ReadAll(r)
	if err != nil {
		return err
	}
	if err := relaySend(s.user, s.from, s.to, raw); err != nil {
		log.Printf("✉️  relay failed from=%s: %v", s.from, err)
		return &gosmtp.SMTPError{Code: 451, Message: "relay failed"}
	}
	log.Printf("✉️  sent: from=%s to=%v size=%d", s.from, s.to, len(raw))
	return nil
}

// relaySend 选择发信通道:配置了 DirectMail SMTP 密码就走原样 SMTP 中继(保留完整
// MIME/附件);否则回退到 DirectMail API(用 Taskly 已有凭证,免单独 SMTP 密码,
// 但只发文本/HTML 正文,附件暂不带)。authUser 为认证用户(作为 API 发信地址)。
func relaySend(authUser, from string, to []string, raw []byte) error {
	if Cfg.RelayPass != "" {
		return relayToDirectMail(from, to, raw)
	}
	subject, text, html := parseMIME(raw)
	account := authUser
	if account == "" {
		account = from
	}
	return services.SendDirectMail(account, "", strings.Join(to, ","), subject, text, html)
}

// parseMIME 从原始邮件中提取主题、纯文本与 HTML 正文
func parseMIME(raw []byte) (subject, text, html string) {
	mr, err := mail.CreateReader(bytes.NewReader(raw))
	if err != nil {
		return "", string(raw), ""
	}
	subject, _ = mr.Header.Subject()
	for {
		p, err := mr.NextPart()
		if err != nil {
			break
		}
		if h, ok := p.Header.(*mail.InlineHeader); ok {
			b, _ := io.ReadAll(p.Body)
			ct, _, _ := h.ContentType()
			if strings.EqualFold(ct, "text/html") {
				html = string(b)
			} else {
				text = string(b)
			}
		}
	}
	return subject, text, html
}

func (s *subSession) Reset()        { s.from = ""; s.to = nil }
func (s *subSession) Logout() error { return nil }

// relayToDirectMail 通过隐式 TLS 连接 DirectMail SMTP,原样转发邮件
func relayToDirectMail(from string, to []string, raw []byte) error {
	if Cfg.RelayUser == "" || Cfg.RelayPass == "" {
		return fmt.Errorf("relay credentials not configured")
	}
	addr := Cfg.RelayHost + ":" + Cfg.RelayPort
	conn, err := tls.Dial("tcp", addr, &tls.Config{ServerName: Cfg.RelayHost})
	if err != nil {
		return err
	}
	c, err := smtp.NewClient(conn, Cfg.RelayHost)
	if err != nil {
		return err
	}
	defer c.Close()

	if err := c.Auth(smtp.PlainAuth("", Cfg.RelayUser, Cfg.RelayPass, Cfg.RelayHost)); err != nil {
		return fmt.Errorf("auth: %w", err)
	}
	if err := c.Mail(from); err != nil {
		return fmt.Errorf("mail from: %w", err)
	}
	for _, rcpt := range to {
		if err := c.Rcpt(rcpt); err != nil {
			return fmt.Errorf("rcpt %s: %w", rcpt, err)
		}
	}
	w, err := c.Data()
	if err != nil {
		return err
	}
	if _, err := w.Write(raw); err != nil {
		return err
	}
	if err := w.Close(); err != nil {
		return err
	}
	return c.Quit()
}
