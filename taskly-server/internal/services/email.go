package services

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"

	"taskly-server/internal/config"

	"github.com/google/uuid"
)

// SendVerificationCode emails a 6-digit code via Aliyun DirectMail (邮件推送).
// If DirectMail isn't configured yet (no verified sender) or the send fails, it
// falls back to logging the code to the server console so registration can still be
// exercised end-to-end during setup. Returns nil on success OR on logged fallback.
func SendVerificationCode(toEmail, code string) error {
	cfg := config.Global.DirectMail
	if cfg.AccessKeyID == "" || cfg.AccountName == "" || strings.Contains(cfg.AccountName, "REPLACE") {
		log.Printf("📧 [DirectMail not configured] verification code for %s = %s", toEmail, code)
		return nil
	}

	region := cfg.Region
	if region == "" {
		region = "cn-hangzhou"
	}
	subject := "Tasket 验证码"
	body := fmt.Sprintf("您的 Tasket 注册验证码是 %s,5 分钟内有效。如非本人操作请忽略。", code)

	params := map[string]string{
		"Action":         "SingleSendMail",
		"AccountName":    cfg.AccountName,
		"AddressType":    "1",
		"ReplyToAddress": "false",
		"ToAddress":      toEmail,
		"Subject":        subject,
		"TextBody":       body,
		"Format":         "JSON",
		"Version":        "2015-11-23",
		"RegionId":       region,
	}
	if cfg.FromAlias != "" {
		params["FromAlias"] = cfg.FromAlias
	}

	// DirectMail's public endpoint is dm.aliyuncs.com (region is passed as RegionId,
	// not in the hostname — dm.<region>.aliyuncs.com does not resolve).
	if err := aliyunRPCPost("https://dm.aliyuncs.com/", cfg.AccessKeyID, cfg.AccessKeySecret, params); err != nil {
		// Don't block registration on a transient mail failure during rollout — log it.
		log.Printf("📧 [DirectMail send failed: %v] verification code for %s = %s", err, toEmail, code)
		return nil
	}
	return nil
}

// aliyunRPCPost signs and sends an Aliyun RPC-style request (HMAC-SHA1, v1.0).
func aliyunRPCPost(endpoint, ak, sk string, params map[string]string) error {
	params["AccessKeyId"] = ak
	params["SignatureMethod"] = "HMAC-SHA1"
	params["SignatureVersion"] = "1.0"
	params["SignatureNonce"] = uuid.NewString()
	params["Timestamp"] = time.Now().UTC().Format("2006-01-02T15:04:05Z")

	keys := make([]string, 0, len(params))
	for k := range params {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var canon strings.Builder
	for i, k := range keys {
		if i > 0 {
			canon.WriteString("&")
		}
		canon.WriteString(pe(k) + "=" + pe(params[k]))
	}
	stringToSign := "POST&" + pe("/") + "&" + pe(canon.String())
	mac := hmac.New(sha1.New, []byte(sk+"&"))
	mac.Write([]byte(stringToSign))
	sig := base64.StdEncoding.EncodeToString(mac.Sum(nil))

	form := url.Values{}
	for k, v := range params {
		form.Set(k, v)
	}
	form.Set("Signature", sig)

	resp, err := http.PostForm(endpoint, form)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return fmt.Errorf("status %d: %s", resp.StatusCode, string(b))
	}
	return nil
}

// pe percent-encodes per Aliyun's RPC signing rules.
func pe(s string) string {
	e := url.QueryEscape(s)
	e = strings.ReplaceAll(e, "+", "%20")
	e = strings.ReplaceAll(e, "*", "%2A")
	e = strings.ReplaceAll(e, "%7E", "~")
	return e
}
