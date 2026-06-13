package mail

import (
	"bufio"
	"os"
	"strings"
	"sync"

	"golang.org/x/crypto/bcrypt"
)

// 账号文件路径,格式每行 email:bcrypt-hash。
// Dovecot 用 passwd-file(BLF-CRYPT)读同一份,做到单一密码来源。
const usersFile = "/etc/luyu-mail/users"

var (
	usersOnce sync.Once
	usersMu   sync.RWMutex
	users     map[string]string // email(小写) -> bcrypt hash
)

// Authenticate 校验邮箱登录密码(用于 SMTP 提交认证;IMAP 由 Dovecot 用同一文件校验)
func Authenticate(email, password string) bool {
	loadUsers()
	usersMu.RLock()
	hash, ok := users[strings.ToLower(strings.TrimSpace(email))]
	usersMu.RUnlock()
	if !ok {
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}

func loadUsers() {
	usersOnce.Do(reloadUsers)
}

func reloadUsers() {
	m := make(map[string]string)
	f, err := os.Open(usersFile)
	if err != nil {
		usersMu.Lock()
		users = m
		usersMu.Unlock()
		return
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		i := strings.IndexByte(line, ':')
		if i <= 0 {
			continue
		}
		email := strings.ToLower(strings.TrimSpace(line[:i]))
		m[email] = strings.TrimSpace(line[i+1:])
	}
	usersMu.Lock()
	users = m
	usersMu.Unlock()
}
