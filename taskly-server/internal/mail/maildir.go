package mail

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"time"
)

// deliverCounter 保证同一进程同一秒内文件名唯一
var deliverCounter uint64

// DeliverMaildir 把一封原始邮件按 Maildir 标准格式投递到某收件人的邮箱目录。
// 目录结构 <root>/<localpart>/{tmp,new,cur},Dovecot 直接读 new/。
// 投递采用「先写 tmp/ 再 rename 到 new/」的原子方式,避免读到半截邮件。
func DeliverMaildir(root, recipient string, raw []byte) error {
	local := localPart(recipient)
	if local == "" {
		return fmt.Errorf("invalid recipient %q", recipient)
	}
	base := filepath.Join(root, local)
	for _, d := range []string{"tmp", "new", "cur"} {
		if err := os.MkdirAll(filepath.Join(base, d), 0o700); err != nil {
			return err
		}
	}

	name := uniqueName()
	tmpPath := filepath.Join(base, "tmp", name)
	newPath := filepath.Join(base, "new", name)

	if err := os.WriteFile(tmpPath, raw, 0o600); err != nil {
		return err
	}
	if err := os.Rename(tmpPath, newPath); err != nil {
		os.Remove(tmpPath)
		return err
	}
	return nil
}

// uniqueName 生成符合 Maildir 约定的唯一文件名:<秒>.<计数>_<随机>.<主机>
func uniqueName() string {
	host, _ := os.Hostname()
	host = strings.NewReplacer("/", "-", ":", "-").Replace(host)
	n := atomic.AddUint64(&deliverCounter, 1)
	b := make([]byte, 4)
	_, _ = rand.Read(b)
	return fmt.Sprintf("%d.%d_%s.%s", time.Now().Unix(), n, hex.EncodeToString(b), host)
}

// localPart 取邮箱地址 @ 前面的部分并转小写
func localPart(addr string) string {
	addr = strings.ToLower(strings.TrimSpace(addr))
	if i := strings.IndexByte(addr, '@'); i > 0 {
		return addr[:i]
	}
	return ""
}
