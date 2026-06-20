# Changelog

本文件记录 Taskly 上线后的重要变更与排障结论。日期为本地时间。

## 2026-06-20

### 排障结论：Apple 登录为什么会失败？（重要，先读这条）

**一句话**：失败的根因是**设备 / 环境侧的 `ASAuthorizationError error 1000`（`.unknown`）**，
发生在 **Apple 授权回调阶段、还没到我们后端**——它**不是某次提交改坏的回归**，也**不是我们能在
代码里直接修好的 bug**。在登录正常的设备上（已登录 iCloud、网络正常）一直是好的。

**判定依据（来自生产 `analytics_events`，6-11 ~ 6-18）：**

- **成功与失败是交错发生的**，不是某个时间点之后全员失败：
  - 成功登录：gold joe（6-11）、Apple John（6-13）、John Apple（6-15 / 6-18）
  - 失败：6-11 / 6-12 / 6-13 / 6-16 / 6-17 / 6-18 各有设备命中
  - → 若是代码回归把它改坏，应表现为"某次发版后全员失败"，而非"有人成功有人失败"。
    交错出现强烈指向**单设备 / 单环境**问题。
- **所有失败的错误码都是 `1000 / .unknown`，`stage=authorization`**——这是
  `SignInWithAppleButton` 的 `onCompletion` 直接回了 `.failure`，**我们的后端代码根本没被调用**。
- 其中 6-13、6-17 各有一台设备在**同一次会话里连点 7 次全失败**——典型的
  "该设备没登录 iCloud / 一直没网 / 双重认证被打断"，越点越失败。
- 历史佐证：上次因 **App Review 点 Apple 按钮"没反应"被拒**，才补了失败弹窗 + 埋点
  （代码注释："App Review rejected exactly this, twice"）。说明它从一开始就是**间歇性失败**，
  并非后来才坏。

**`error 1000 / .unknown` 的常见真实成因（都在设备侧）：**
1. 设备未登录 iCloud / Apple ID（App Review、全新测试机最常见）；
2. 授权瞬间无网络或网络抖动；
3. 双重认证（2FA）弹窗被系统打断。

**所以我们能做的不是"修好 1000"，而是让它不再是死胡同、并且可观测**——见下面的改动。

### 新增 / 变更

- **Apple 登录失败兜底（iOS `LoginView`）**：失败弹窗从只有「OK」改为多一个
  **「Create account with email」**，一键切到邮箱注册。此前新用户撞到 1000 时无路可走
  （提示"用邮箱密码登录"但他们根本还没有账号）。文案也改为如实说明"通常是 Apple/网络的临时问题，
  可重试或改用邮箱注册"。
- **漏斗埋点补全（iOS）**：此前只在**成功时**埋点，失败完全不可见。新增
  - `apply_attempt` / `apply_success` / `apply_failed`（ApplyView 此前点进去后零埋点）
  - `post_task_attempt` / `post_task_failed`（保留原成功事件 `post_task_submit`）
  - `post_service_attempt` / `post_service_failed`（保留原 `post_service_submit`）
  - `*_failed` 均带 `desc` 并立即 `flush`，下个版本即可区分"用户放弃"与"请求失败"。

### 安全修复（后端，已部署）

- **Apple 身份令牌完整验签**（`auth.go`：`parseAppleToken` → `verifyAppleToken`）。
  此前后端只解 JWT payload、**不验签名**，任何伪造 token（`iss=appleid.apple.com`）即可冒充任意
  Apple 用户登录。现改为：
  - **RS256 签名验证**，对照 Apple 公钥 `appleid.apple.com/auth/keys`（JWKS 缓存，TTL 1h，
    按 `kid` 轮换自动刷新，刷新失败回退旧缓存）；
  - 校验 `iss` / `aud`(= bundle id `com.taskly.app`) / `exp`；
  - **nonce 重放保护**：token 含 `nonce` 时校验 `sha256hex(rawNonce) == token.nonce`。
  - **向后兼容**：旧版 app 不带 nonce、token 也无 nonce claim 时跳过该项，签名/aud 仍为硬性闸门，
    线上已发版 app 的登录不受影响。
- **iOS 配合 nonce**（`AuthManager` + `LoginView`）：每次请求生成随机 rawNonce，
  `request.nonce = sha256(rawNonce)`，原始值随登录请求发给后端校验。
- **验证**：构造 `iss`/`aud` 正确但签名伪造的 token → 线上返回 **401 `invalid apple token`**，
  且数据库未生成该用户。冒充漏洞已堵死。

> 注意：上面这条后端安全修复**与"为什么登录失败"无关**——它修的是"伪造 token 能登录"的安全洞，
> 不是 error 1000。两件事别混。
