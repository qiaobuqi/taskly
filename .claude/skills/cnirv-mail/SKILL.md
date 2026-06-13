---
name: cnirv-mail
description: >-
  Operational + usage runbook for the self-hosted company email platform on the
  m.cnirv.com domain (mailboxes like luyutech@m.cnirv.com), built into the Taskly
  Go backend (taskly-server/internal/mail) with Dovecot for IMAP. Use this whenever
  someone wants to add a mailbox to a mail client (网易邮箱大师 / Apple Mail / Outlook /
  Foxmail) and asks for IMAP/SMTP server settings, "邮箱怎么添加 / 收发邮件配置 / IMAP
  端口", create a NEW mailbox account or change a mailbox password, asks "邮件收不到 /
  发不出去 / 客户端登录失败" or how the cnirv/luyu mail system works, where the mail
  config/Maildir/certs live, or needs to operate/debug receiving (port 25), submission
  (587/465), or IMAP (993). This is the source of truth for the mail platform — check
  here before grepping the server or guessing client settings.
---

# cnirv-mail — 自建企业邮箱平台运维手册

一套从 0 到 1 自建的企业邮箱,域名 `m.cnirv.com`(地址形如 `luyutech@m.cnirv.com`),
能跟任意外部邮箱(Gmail/QQ/163…)互发互收,并能用普通邮件客户端收发。

**代码并入 Taskly**,不是独立项目:`taskly-server/internal/mail/`,跟 Taskly 同一个二进制、
同一个 systemd 服务 `taskly-server`、同一次部署。相关:[[taskly-deployment]] [[taskly-ops]]。

## 1. 客户端添加邮箱(最常被问)

任何标准 IMAP 客户端都能加。给用户这套设置:

```
邮箱地址 / 用户名:  luyutech@m.cnirv.com   (用完整邮箱做用户名)
密码:              <邮箱登录密码,见第 4 节>
收件服务器 IMAP:    mx.cnirv.com   端口 993   加密 SSL/TLS
发件服务器 SMTP:    mx.cnirv.com   端口 465   加密 SSL/TLS  (或 587 STARTTLS)
```

- **网易邮箱大师**:添加邮箱 → 选「其他邮箱」→ 输入邮箱+密码 → 若自动检测失败选「手动配置/IMAP」按上表填。
- **iPhone 自带「邮件」**:设置 → 邮件 → 账户 → 添加账户 → 其他 → 添加邮件账户 → 按上表填(对自定义域名最稳)。
- 客户端里「发件 SMTP 密码」也填**同一个邮箱密码**——客户端连的是我们服务器,服务器内部再中继出去。

加不上时先按第 5 节排查;若某个客户端(网易对自定义域名较挑)始终不行,让用户换 Apple Mail/Outlook 验证,基本必成。

## 2. 架构(一句话掌握)

```
收信:  外部MTA ──:25──▶ taskly-server 内置 go-smtp 收信器 ──▶ Maildir(/var/mail/luyu/<用户>)
读信:  客户端 ──:993 IMAP SSL──▶ Dovecot ──▶ 读同一个 Maildir
发信:  客户端 ──:465/587 AUTH──▶ taskly-server 内置提交服务 ──▶ 阿里云 DirectMail ──▶ 外部
```

- 一个 `taskly-server` 进程同时监听 `8430`(Taskly API)+ `25` + `587` + `465`;Dovecot 单独进程监听 `993`。
- 发信中继两通道:配了 `MAIL_RELAY_PASS`(DirectMail SMTP 密码)走**原样 SMTP 中继**(保留附件);
  否则回退 **DirectMail API**(复用 Taskly 已有 AccessKey,免单独密码,但只发文本/HTML 正文,附件暂不带)。
- DirectMail 是出站发信中继(阿里云对出站 25 端口封禁,必须走中继);收信是我们自建,不经 DirectMail。

## 3. 服务器上的关键位置(server: root@47.94.93.24)

| 东西 | 位置 |
|------|------|
| 服务 | systemd `taskly-server`(`/etc/systemd/system/taskly-server.service`,含 MAIL_* 环境变量 + `AmbientCapabilities=CAP_NET_BIND_SERVICE`) |
| 二进制 | `/opt/apps/taskly-server/bin/taskly-server` |
| 邮箱账号文件 | `/etc/luyu-mail/users`(每行 `email:bcrypt哈希`,root:appuser 640 + ACL u:dovecot:r) |
| 邮件存储 Maildir | `/var/mail/luyu/<本地名>/{new,cur,tmp}`(owner appuser 999:988) |
| Dovecot 配置 | `/etc/dovecot/dovecot.conf`(独立精简配置;原始备份 `.orig`) |
| TLS 证书(给提交服务) | `/etc/luyu-mail/tls/{fullchain,privkey}.pem`(LE mx.cnirv.com 的 appuser 可读副本;certbot deploy-hook 续期重做) |
| 收信日志 | `journalctl -u taskly-server | grep 📬`;发信 `grep ✉️`;Dovecot `/var/log/dovecot.log` |

代码:`taskly-server/internal/mail/`(receiver.go 收信、submission.go 提交+中继、maildir.go 投递、
accounts.go bcrypt 认证、config.go 读 MAIL_* 环境变量)。

## 4. 新建邮箱账号 / 改密码

账号 = `/etc/luyu-mail/users` 里一行 `email:bcrypt哈希`。Dovecot 和 Go 提交服务共用这份文件。

**生成 bcrypt 哈希**(本地 Taskly 仓库内,$2a 两边都兼容):
```bash
cd taskly-server && mkdir -p tmpgen
cat > tmpgen/main.go <<'EOF'
package main
import ("fmt";"os";"golang.org/x/crypto/bcrypt")
func main(){ h,_:=bcrypt.GenerateFromPassword([]byte(os.Args[1]),10); fmt.Print(string(h)) }
EOF
go run ./tmpgen '你的明文密码'; rm -rf tmpgen
```

**写入服务器**(追加新账号;改密码则替换对应行):
```bash
# 新建 newuser@m.cnirv.com:
ssh root@47.94.93.24 "echo 'newuser@m.cnirv.com:<上面的哈希>' >> /etc/luyu-mail/users && \
  chown root:appuser /etc/luyu-mail/users && chmod 640 /etc/luyu-mail/users && \
  setfacl -m u:dovecot:r /etc/luyu-mail/users && systemctl restart taskly-server"
```

要点:
- **scp 覆盖整个文件后**必须重设 owner/perm/ACL(scp 会重置),否则 Dovecot 读不到 → 认证临时失败。
- 改密码后**重启 taskly-server**:Dovecot 立即生效,但 Go 提交服务的账号缓存只在启动时加载,需重启才认新密码。
- 收信对**任意** `@m.cnirv.com` 都接收(收信器只校验域名后缀),但只有 users 文件里有的账号才能登录 IMAP/发信。
- 若要这个地址能**对外发信**,它得是 DirectMail 的已验证发信地址(控制台「发信地址」新建),否则 API 中继会报地址未找到。

## 5. 排查(按顺序)

**客户端登录失败 / 收不到信:**
1. 服务在跑、端口在听:`ssh root@47.94.93.24 'systemctl is-active taskly-server dovecot; ss -tlnp | grep -E ":25 |:465 |:587 |:993 "'`
2. 服务器本机 IMAP 登录:用 `python3 imaplib.IMAP4_SSL("127.0.0.1",993).login(邮箱,密码)` 验证账号/密码/Dovecot。
3. 公网路径(本机网络常有 DNS 劫持测不准,**从服务器连自己公网 IP**):
   `ssh root@47.94.93.24 'echo|openssl s_client -connect 47.94.93.24:993 -servername mx.cnirv.com 2>/dev/null|openssl x509 -noout -subject -dates'`
4. Dovecot 认证报错看 `/var/log/dovecot.log`;常见是 `/etc/luyu-mail/users` 权限/ACL 丢失(见第 4 节)。
5. DNS:从服务器查 `dig +short m.cnirv.com MX`(应 → mx.cnirv.com → 47.94.93.24)。**别在本地机器查 DNS/端口**(有 sinkhole,返回 198.18.0.x 假地址)。

**发不出去:**
1. 看发信日志:`journalctl -u taskly-server | grep ✉️`(`sent` = 成功;`relay failed` = 中继失败)。
2. 测提交+发信:服务器上 `smtplib.SMTP_SSL("mx.cnirv.com",465).login(...).send_message(...)` 发到 Gmail。
3. 走 API 通道时,发信地址必须是 DirectMail 已验证发信地址;否则报 "mail address is not found"(新建地址有生效延迟,重试几次)。

**端口/网络层:** 阿里云安全组 `sg-2ze7afu9o0olr62q65hr`(cn-beijing)+ ufw 需放行 25/465/587/993;
出站 25 被阿里云封死(正常,发信走 DirectMail 不受影响)。

## 6. DNS(阿里云,cnirv.com 区,aliyun CLI 可改)

| 记录 | 主机记录 | 值 | 作用 |
|------|---------|-----|------|
| A | mx | 47.94.93.24 | 邮件主机 |
| MX | m | mx.cnirv.com (10) | 收信入口 |
| TXT | m | `v=spf1 include:spf1.dm.aliyun.com -all` | SPF |
| TXT | _dmarc.m | `v=DMARC1; p=none; rua=mailto:dmarc@cnirv.com` | DMARC |
| TXT | aliyun-cn-hangzhou._domainkey.m | (DirectMail 给的 DKIM 公钥) | DKIM |

**不要动 apex `cnirv.com` 的 MX**——它指向 DirectMail,Taskly 发信靠它;改了会搞坏 Taskly。
邮箱域用子域 `m.cnirv.com` 就是为了与之隔离。

## 7. 重新部署

跟 Taskly 一起部署(同一二进制)。最简手动流程:
```bash
cd taskly-server && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /tmp/ts ./cmd
scp /tmp/ts root@47.94.93.24:/tmp/ts
ssh root@47.94.93.24 'install -o appuser -g appuser -m755 /tmp/ts /opt/apps/taskly-server/bin/taskly-server && systemctl restart taskly-server'
```
启动需等 ~12s 连数据库;`curl -s http://127.0.0.1:8430/v1/health` 返 200 即就绪。重启不影响 Dovecot(独立进程)。
