# Taskly — App Store Connect 提交内容(直接复制粘贴)

> Bundle ID: `taskly.cnirv.com` ·复用已有 App 记录(原“来活儿”)。下面每一项标了对应后台位置。

---

## 0. 被拒修复(2026-06-09 审核 · Submission 4edf420a) — 必读

这次被拒 5 条,**3 条代码已修,2 条你在 ASC 改设置**。逐条对应:

| 驳回条款 | 问题 | 处理 |
|---|---|---|
| **2.1(a) 完整性** | Sign in with Apple 按钮无反应 | ✅ **代码已修**。根因:`Taskly.entitlements` 是空的,没有 `com.apple.developer.applesignin`,所以 `ASAuthorizationController` 一调起就报 error 1000,旧代码又把 `.failure` 静默吞掉,表现就是"点了没反应"。已加 entitlement + 把错误弹给用户。⚠️ 见下方「Apple 开发者后台」一步。 |
| **1.2 UGC 安全** | 缺少屏蔽用户机制 | ✅ **代码已修**。任务详情右上角 `···` 和聊天页右上角 `···` 都加了「Block this user」:即时把对方任务/消息从你的列表移除,并自动给开发者发一条 Report(24h 内人工处理)。另加了服务端脏词过滤(发任务/发消息)。 |
| **2.3 元数据** | 找不到"发任务时加照片"功能 | ✅ **代码已修**。发任务页(Post Task)新增「Photos」区,可加最多 6 张照片,上传后随任务提交。 |
| **2.3.6 年龄分级** | 没勾 Messaging and Chat | ⚠️ **你在 ASC 改**:App 信息 → 年龄分级 → 「Messaging and Chat」选 **Yes**。 |
| **2.3.6 年龄分级** | 没勾 User-Generated Content | ⚠️ **你在 ASC 改**:同页 「User-Generated Content」选 **Yes**。 |

### ⚠️ Apple 开发者后台必做(Sign in with Apple 才能真正生效)
代码加了 entitlement,但 App ID 也要开能力,否则正式包仍会签名失败/按钮无效:
1. developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → `taskly.cnirv.com`
2. 勾选 **Sign In with Apple** → Save(自动签名 / fastlane 重新打包时会带上 profile)。

> 用自动签名(本项目 `CODE_SIGN_STYLE: Automatic`)时,Xcode/fastlane 打包通常会自动在 App ID 上启用该能力;若打包报 provisioning 错误,就按上面手动勾一次。

### 回复审核(Resolution Center)要附:屏蔽演示录屏
1.2 要求**真机录屏**演示「屏蔽用户」。录这一段即可:打开任意任务详情 → 右上角 `···` → **Block this user** →(回到列表,该用户任务消失)。把录屏放到 App Review Information → Notes,并在 Resolution Center 回复说明上述 5 条均已处理。

---

## 1. App 隐私「营养标签」(App 信息 → App 隐私 → 编辑)

和 `PrivacyInfo.xcprivacy` 完全一致。逐条勾选下面的数据类型;**全部:关联到用户身份=是,用于追踪=否**。

| App Store Connect 数据类型 | 路径 | 用途 |
|---|---|---|
| **Email Address** | Contact Info → Email Address | App Functionality(登录/账号) |
| **Name** | Contact Info → Name | App Functionality(昵称/资料) |
| **Payment Info** | Financial Info → Payment Info | App Functionality(支付/担保交易) |
| **Other User Content** | User Content → Other User Content | App Functionality(任务详情、图片、聊天) |
| **Photos or Videos** | User Content → Photos or Videos | App Functionality(实名认证上传的证件照) |
| **Product Interaction** | Usage Data → Product Interaction | **Analytics**(留存/日活埋点) |

> 已**删除** Coarse Location(App 没有任何定位调用,申报会与实际不符)。证件照属敏感内容:隐私政策页已加"实名认证"条款说明。

问卷里每一项会问三步,统一这样答:
1. Do you collect this data? → **Yes**
2. Is it linked to the user's identity? → **Yes**(以上全部)
3. Is it used for tracking? → **No**(以上全部;我们不做跨 App 广告追踪)

> ⚠️ 不要勾任何「Used for Third-Party Advertising / Developer's Advertising」——我们没有广告 SDK,`NSPrivacyTracking=false`。

---

## 2. 隐私政策 URL(App 隐私 → Privacy Policy URL)

```
https://taskly.cnirv.com/privacy
```
服务条款(如有「License Agreement / Terms」字段):
```
https://taskly.cnirv.com/terms
```
> 这两个页面已部署、HTTPS 可访问(应用内「设置 → Privacy Policy / Terms」也是打开这两个 URL)。

---

## 3. App 审核备注(版本 → App Review Information → Notes)+ 演示账号

**Sign-In required: Yes**,填演示账号:

```
User name: appreview@taskly.app
Password:  Review2026!
```

Notes(英文,直接贴):

```
Taskly is a local task & services marketplace (similar to Airtasker).

DEMO ACCOUNT
  Email:    appreview@taskly.app
  Password: Review2026!

GUEST BROWSING
  Login is optional. You can tap "Skip" on the sign-in screen to browse
  tasks without an account. Posting a task, applying for a task, messaging,
  and the profile/wallet tabs prompt sign-in (Guideline 5.1.1 — login is
  only required for account-specific features).

PAYMENTS (test mode)
  Payments are processed by Stripe in TEST mode for this review build.
  Use Stripe test card:
     Card number: 4242 4242 4242 4242
     Expiry:      any future date (e.g. 12/30)
     CVC:         any 3 digits (e.g. 123)
     ZIP:         any (e.g. 2000)
  Funds are held in escrow and released to the worker when the poster
  confirms completion. This is payment for real-world services performed
  off-app, so it is out of scope for In-App Purchase (Guideline 3.1.3(e)/3.1.5).

ACCOUNT DELETION
  Settings (gear icon, top-right of Profile) → Delete Account.

There are several sample tasks pre-seeded so the board is populated.
```

> 演示账号、两个示例发布者(Sarah M. / Mike T.)和 6 条示例任务已在线上库里建好。

---

## 4. 截图(版本 → 各机型尺寸)

App Store 当前**必传 6.9″ iPhone**(1320×2868);本 App 仅 iPhone,不声明 iPad,所以只需 6.9″。

✅ **已生成 5 张,精确 1320×2868,可直接上传** —— 在 `docs/screenshots/`:
| 顺序 | 文件 | 内容 |
|---|---|---|
| 1 | `02-board.png` | 任务列表(首页,Taskly 标题) |
| 2 | `03-detail.png` | 任务详情 |
| 3 | `08-post.png` | 发布任务 |
| 4 | `07-wallet.png` | 钱包 / 收益 |
| 5 | `06-profile.png` | 个人资料 |

备选:`04-guest-gate.png`(游客登录拦截页)、`05-login.png`(登录页)。
> 都是真机模拟器原图、无边框,符合 ASC 上传规格。若想要带文案/设备外框的营销图,可再用 `app-store-screenshots` skill 加工。

---

## 5. 元数据(App 信息 / 版本信息)

**Name(≤30):** (注:"Taskly" 单词已被他人占用,改用唯一长名;主屏图标名仍是 Taskly)
```
Taskly: Local Tasks & Help
```
**Subtitle(≤30 字符,当前 25):**
```
Post tasks, get them done
```
**Promotional Text(≤170,可随时改,不需重新审核):**
```
Need a hand? Post a task in seconds and get matched with locals ready to help — repairs, moving, errands, tech setup and more.
```
**Keywords(≤100,逗号分隔、词间不要空格):**
```
handyman,tasker,errand,gig,chore,haul,repair,fix,hire,clean,garden,paint,jobs,mount,move,yard,setup
```
**Description:**
```
Taskly is the easiest way to get everyday tasks done — and to earn money helping others nearby.

POST A TASK IN SECONDS
Tell us what you need done, set your budget, and add a photo. From a leaking tap to moving day, flat-pack assembly to setting up Wi-Fi, locals are ready to help.

FIND WORK NEARBY
Browse open tasks around you, filter by category, and apply with your price. Build your rating with every job you complete.

SAFE, SECURE PAYMENTS
Pay through the app and your money is held securely until the job is done. Release payment when you're happy with the work — then withdraw your earnings straight to your balance.

CHAT IN APP
Message the other person to agree on details before you start. Everything stays in one place.

WHY TASKLY
• Browse freely — sign in only when you post or apply
• Transparent pricing, no hidden fees
• Ratings and reviews on every profile
• Categories: Repair, Moving, Errands, IT & Tech, and more

Download Taskly and get it done today.
```
**Primary Category:** `Lifestyle`
**Secondary Category(可选):** `Business`

**Support URL(必填):**
```
https://taskly.cnirv.com/support
```
> ✅ 已部署专门的联系页(含 support@cnirv.com、常见问题、账号删除指引、隐私/条款链接)。
**Marketing URL(可选):** 留空即可。

**Copyright:** `© 2026 cnirv`
**Age Rating:** 走问卷。**本次被拒明确要求**:「Messaging and Chat」选 **Yes**、「User-Generated Content」选 **Yes**(App 有聊天 + 用户发任务)。其余基本 None。App 已具备举报(Report)+ 屏蔽(Block)+ 脏词过滤,满足 UGC 前置条件。见第 0 节。

---

## 6. Apple Pay 按钮(可选,不影响上线)

银行卡支付已经能用。若要在支付页显示「Apple Pay」按钮:
1. developer.apple.com → Identifiers → 注册 Merchant ID `merchant.com.taskly.app`
2. 在 Stripe Dashboard 关联该 Merchant ID(Settings → Payments → Apple Pay)
3. 在 Xcode 的 Taskly.entitlements 加 `com.apple.developer.in-app-payments` = `merchant.com.taskly.app`
   不做的话保持现状即可(entitlements 留空,卡支付正常)。

---

## 7. 上传构建版本(fastlane)

fastlane 已配置(见 memory: taskly-fastlane,共用 ASC API key)。
```bash
cd taskly-ios
bundle exec fastlane beta        # 打包并上传到 TestFlight
# 或上架审核
bundle exec fastlane release
```
> 上传是对外动作 —— 你确认后我再执行,或你自己跑。构建上去后,在 ASC 把这一版选为审核版本,填上面 1–5 项即可提交。

---

## 已替你完成 ✅
- 线上后端已修复**游客浏览**:`GET /tasks`、`/tasks/:id`、`/services`、`/users/:id` 改为可匿名访问(写操作仍需登录),已部署并验证 HTTPS 通。
- 演示账号 + 6 条示例任务已建好(线上库)。
- **5 张 6.9″ 截图**已生成(`docs/screenshots/`,1320×2868,可直接传)。
- 钱包 Withdraw 按钮蓝→**品牌绿**。
- **隐私清单**:删除了 Coarse Location(无定位调用),补充了 Photos or Videos(实名证件照)。
- **实名认证**做完整:补了「已拒绝」状态可重新提交、改正了「approved」误导文案;隐私政策页加了实名认证条款。已在模拟器端到端跑通(填名→选证件照→提交→Under Review)。
- `ITSAppUsesNonExemptEncryption: false`(免出口合规追问)。
- 服务端隐私/条款页标题 Tasket→**Taskly**(与 App 名一致),已部署。
- 隐私&条款页 / 账号删除 / 隐私弹窗 / 测试数据清理 —— 之前已完成。

## ⚠️ 上线前务必处理(非审核拦截、但影响真实用户)
- **Stripe 还是 test key**:审核 OK(审核员用测试卡),但正式上线前要在 `config.prod.yaml` 换成 live key,否则真实用户付不了款。
- **App 名 "Taskly" 撞名风险**:你已确认走 "Taskly: Local Tasks & Help" 长名 + 显示名 Taskly。若 ASC 提示名称被占或被以 4.1/5.2.1 驳回,就得换更独特的名字。

## 仍需你在 ASC 手动操作的 ⚠️
1–5 项内容已写好,逐项粘贴即可:① 隐私营养标签 ② 隐私政策 URL ③ 审核备注+演示账号 ④ 上传 5 张截图 ⑤ 元数据。
**第 7 项上传构建** 是对外动作,确认后我再跑 fastlane(或你自己跑)。
