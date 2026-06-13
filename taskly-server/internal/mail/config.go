package mail

import (
	"os"
	"strconv"
)

// Config 邮件子系统配置。通过环境变量注入(systemd 里配),默认值适配当前部署。
type Config struct {
	Enabled         bool   // 总开关:MAIL_ENABLED=1 才启动收信/提交服务
	MailDomain      string // 本域,只接收 @MailDomain 的信,如 m.cnirv.com
	Hostname        string // SMTP 主机名(HELO/证书 CN),如 mx.cnirv.com
	ReceiveAddr     string // 收信监听地址,默认 :25
	SubmissionAddr  string // 提交监听地址(STARTTLS),默认 :587
	SubmissionsAddr string // 提交监听地址(隐式 TLS),默认 :465
	MaildirRoot     string // Maildir 根目录,默认 /var/mail/luyu
	TLSCert         string // TLS 证书路径(提交服务用)
	TLSKey          string // TLS 私钥路径
	MaxMessageBytes int64

	// 出站中继:把客户端提交的邮件转给阿里云 DirectMail SMTP 发出
	RelayHost string // smtpdm.aliyun.com
	RelayPort string // 465
	RelayUser string // DirectMail 发信地址,如 luyutech@m.cnirv.com
	RelayPass string // 该地址在 DirectMail 控制台设置的 SMTP 密码
}

// Cfg 全局邮件配置,InitConfig 后可用
var Cfg Config

// InitConfig 从环境变量加载邮件配置
func InitConfig() {
	Cfg = Config{
		Enabled:         os.Getenv("MAIL_ENABLED") == "1",
		MailDomain:      env("MAIL_DOMAIN", "m.cnirv.com"),
		Hostname:        env("MAIL_HOSTNAME", "mx.cnirv.com"),
		ReceiveAddr:     env("MAIL_RECEIVE_ADDR", ":25"),
		SubmissionAddr:  env("MAIL_SUBMISSION_ADDR", ":587"),
		SubmissionsAddr: env("MAIL_SUBMISSIONS_ADDR", ":465"),
		MaildirRoot:     env("MAIL_MAILDIR_ROOT", "/var/mail/luyu"),
		TLSCert:         env("MAIL_TLS_CERT", "/etc/letsencrypt/live/mx.cnirv.com/fullchain.pem"),
		TLSKey:          env("MAIL_TLS_KEY", "/etc/letsencrypt/live/mx.cnirv.com/privkey.pem"),
		MaxMessageBytes: envInt("MAIL_MAX_BYTES", 25*1024*1024),
		RelayHost:       env("MAIL_RELAY_HOST", "smtpdm.aliyun.com"),
		RelayPort:       env("MAIL_RELAY_PORT", "465"),
		RelayUser:       env("MAIL_RELAY_USER", ""),
		RelayPass:       env("MAIL_RELAY_PASS", ""),
	}
}

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func envInt(k string, def int64) int64 {
	if v := os.Getenv(k); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			return n
		}
	}
	return def
}
