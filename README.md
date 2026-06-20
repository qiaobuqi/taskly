# Taskly

跑合本地任务的双边市场:Go 后端(`taskly-server`,gin + gorm/MySQL)+ SwiftUI app(`taskly-ios`)。

- 本地联调 / 生产部署 / 密钥位置:见 `.claude/skills/taskly-ops`(运维手册)与 `CHANGELOG.md`。
- 生产:`root@47.94.93.24:8430`,域名 `https://taskly.cnirv.com`,RDS 库 `taskly`。

---

## ⚠️ 易踩的坑(改之前先读,避免重复踩)

### 1. iOS bundle id 必须和后端 `apple.bundle_id`(Apple 登录 `aud`)保持一致

**约束**:Apple「Sign in with Apple」签发的 identity token,其 `aud` 字段 = **app 的实际 bundle
id**。后端 `verifyAppleToken`(`taskly-server/internal/handlers/auth.go`)会校验 `aud` ∈
`config.apple.bundle_id`。**两者一旦不一致,所有真实 Apple 登录会被后端判为 `invalid audience`
→ 401,登录全挂。**

- 当前真实 bundle id:**`taskly.cnirv.com`**(在 `Taskly.xcodeproj/project.pbxproj` 的
  `PRODUCT_BUNDLE_IDENTIFIER`,Debug/Release 都是)。
  - 历史:最初是 `com.taskly.app`,在提交 `c435788`(App Store readiness)改成 `taskly.cnirv.com`。
- 后端配置 `apple.bundle_id` 支持**逗号分隔的允许列表**,当前值
  `"taskly.cnirv.com,com.taskly.app"`(新旧都收,避免改名期把人锁死)。
  - 本地:`taskly-server/configs/config.yaml`
  - 生产:`/opt/apps/taskly-server/configs/config.prod.yaml`(server-only,改完
    `systemctl restart taskly-server`)。

**改 bundle id 时务必同步更新这两处后端配置**,否则 Apple 登录会静默全挂。
(教训:2026-06-20 后端 `aud` 仍写着旧的 `com.taskly.app`,一次验签上线把真实登录全拒了。)

**自查**:抓一条真实 token 解 payload 看 `aud`,或本地用真 token 跑验签:
```bash
# 真实 Apple token 的 aud 必须出现在 config.apple.bundle_id 里
```

### 2. `error 1000`(`ASAuthorizationError.unknown`)不是后端/代码 bug

Apple 登录失败若 `stage=authorization` + `code=1000`,是**授权回调阶段失败、根本没到后端**,
属于**设备/环境侧**:设备没登录 iCloud、授权瞬间断网、2FA 被打断。代码改不掉,别往后端找。
app 端已做兜底(失败弹窗给「用邮箱注册」入口)。详见 `CHANGELOG.md` 2026-06-20 条。

### 3. Apple identity token 必须验签,不能只解 payload

后端早期版本只 base64 解 JWT payload 取 `sub`、**不验签名**,任何伪造 token 即可冒充任意用户。
现已改为完整 RS256 验签(对照 `appleid.apple.com/auth/keys`)+ 校验 `iss`/`aud`/`exp`/`nonce`。
**不要回退成只解 payload 的写法。**

### 4. 生产 DB / Stripe 密钥只在服务器上

真密钥只在 `config.prod.yaml`(server-only,不进 git)。本地 `config.yaml` 只放占位/dev 值。
Stripe test key 还做了 IP 白名单(只允许生产服务器),支付流程必须在服务器上测。见 `taskly-ops`。
