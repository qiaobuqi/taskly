# Taskly 提审前自查报告(App Store Review)

**设备:** iPad Air 11-inch (M3) · iPadOS 26 模拟器(= App Review 拒审同款设备)+ iPhone 17 Pro 对照
**构建:** Release 配置(指向生产后端 `https://taskly.cnirv.com/v1`)· Bundle `taskly.cnirv.com`
**日期:** 2026-06-10 · 驱动方式:AXe(accessibility) + simctl 截图
**对照拒审:** Submission `4edf420a` · 5 条问题 / 4 个 Guideline
**规则基准:** App Store Review Guidelines,2026-06-09 与官网核对

---

## 摘要(读这段就够)

Taskly 针对上次拒审,**代码层面的修复其实大多已经做了**:隐私同意页、隐私政策/条款、账号删除、Report/Block 审核弹窗、"Add a Photo"、SIWA entitlement、PrivacyInfo.xcprivacy 全在。

**但有一个致命的 iPad 专属 bug,把好几条拒审同时引爆了。** 经 iPhone/iPad A/B 实测证明:

> **App 是纯 iPhone 应用(`TARGETED_DEVICE_FAMILY = 1`),在 iPad 上以 iPhone 兼容模式运行时,所有 `.sheet` 模态弹窗都无法呈现 —— 同一个包在 iPhone 上一切正常。**

App Review 在 iPad Air 上测,于是:**登录页弹不出 → "Sign in with Apple 无响应"(2.1a);发任务要先登录、登录弹不出 → reviewer 进不去发布页、找不到 "Add a Photo"(2.3);举报/拉黑弹窗弹不出 → reviewer 要的 block 录屏做不出(1.2)。** 修好这一个 bug,2.1a / 2.3 / 1.2 大概率一起解决。剩下 2.3.6 ×2 是纯 App Store Connect 年龄分级勾选。

**可提审判断:❌ 暂不可提审** —— 必须先修复 iPad 模态弹窗,并在真机/iPad 模拟器上回归。

---

## ✅ 回归验证(2026-06-10,修复后)

把 `TARGETED_DEVICE_FAMILY` 从 `1` 改成 `1,2`(Debug + Release 两处),Release 重新构建后在同一台 iPad Air 11" (M3) 上用 AXe 跑了同样的流程,**三个弹窗全部恢复正常**:

| 流程 | 修复前 iPad | 修复后 iPad |
|---|---|---|
| 启动布局 | iPhone 兼容模式居中缩放窗口 | ✅ 原生 iPad 全屏布局(`axe-audit-ipad/01-launch.png`) |
| Me → "Sign In" → 登录页 | ❌ 无弹窗 | ✅ 弹出 Email/Password/**Sign in with Apple**/Skip(`axe-audit-ipad/04-login.png`) |
| 任务详情 → "⋯ More" → 审核弹窗 | ❌ 无弹窗 | ✅ 弹出 Report this user / Block this user / "Reports reviewed within 24 hours"(`axe-audit-ipad/06-moderation.png`) |

**结论:根因证实且已修复。** 2.1(a) / 1.2 / 2.3 的连带阻断随此修复一并解除。剩余待办:① App Store Connect 年龄分级勾 Messaging and Chat = Yes、User-Generated Content = Yes(2.3.6 ×2);② iPhone 真机录 block 流程 + 填 demo 账号写进 App Review 备注;③ 建议补 iPad 布局打磨 + Tab Bar 无障碍 label。

---

## 决定性证据:iPhone / iPad A/B 对照

同一个 Release 包,同样的 AXe 操作(点游客 Profile 的 "Sign In"):

| 操作 | iPhone 17 Pro | iPad Air 11" (M3) |
|---|---|---|
| 点 "Sign In" → 登录页 | ✅ 弹出 Email / Password / **Sign in with Apple** / Skip(见 `iphone-03-signin.png`) | ❌ 界面不变,无任何弹窗(见 `axe-audit/08-login.png`) |
| 任务详情点 "⋯ More" → 审核弹窗 | ✅ 弹出 "Report or Block / Report this user / Block this user / Reports reviewed within 24 hours"(`iphone-04-moderation.png`) | ❌ 界面不变,无弹窗(`axe-audit/06-moderation.png`) |

因为 iPhone 用**完全相同**的驱动方法可正常弹出,排除了"AXe 点击没生效"的可能 —— 这是**真实的 iPad app bug**。

接线本身正确:`SignInPromptView` 的按钮 = `router.showLogin = true`,`RootView` 里 `.sheet(isPresented:$router.showLogin){ LoginView() }`;`TaskDetailView` 的 ⋯ = `showReport=true` → `.sheet{ ModerationSheet }`。代码没错,**是兼容模式下模态呈现整体失效**。

---

## 逐条对照拒审(5 条)

### ❌ Guideline 2.1(a) — Sign in with Apple 无响应 [阻断]
- **根因(已证明):** iPad 兼容模式下登录 `.sheet` 不present,SIWA 按钮根本到不了。代码与 entitlement(`com.apple.developer.applesignin`)都正常。
- **修复方向:**
  1. **首选:正式支持 iPad** —— `TARGETED_DEVICE_FAMILY = 1,2`,适配 size class,并在 iPad 上回归所有模态流程。被 iPad 审就该是真 iPad app。
  2. 若坚持纯 iPhone:必须让兼容模式下的模态呈现可用(排查 scene/window 配置),并**亲自在 iPad 上验证**——开发显然只在 iPhone 测过。
  3. 兜底:无论如何,在 App Review Information 备注里提供 **email+password demo 账号**,别让 reviewer 卡在登录。

### ❌ Guideline 1.2 — UGC 审核措施(要 block 录屏) [阻断]
- **现状:** `ModerationSheet` 实现完整 —— Report + Block,"24 小时内审核""拉黑即时隐藏",block 同时 POST `/reports` 通知开发者。**符合 1.2 要求。**
- **问题:** 同一弹窗 bug,iPad 上打不开 → reviewer 要的 block 机制录屏无法演示。
- **修复:** 随弹窗 bug 一并解决后,**在 iPhone 真机录制 block 流程**(reviewer 明确要"physical device"录屏),放进 App Review 备注。补充:确认有内容过滤、举报、零容忍 EULA、24h 处理流程(代码里 report/block 已具备,其余确认即可)。

### ❌ Guideline 2.3 — "Add a Photo" 找不到 [阻断]
- **现状:** `PostTaskView` 里**确实有** `PhotosPicker`,label 就叫 "Add a Photo",最多 6 张。功能存在。
- **根因:** 发任务需先登录;iPad 上登录弹不出 → reviewer 进不去发布页,自然"找不到"该功能。**是登录 bug 的连带后果。**
- **修复:** 修好登录后此项大概率自动消除。稳妥起见,在备注里说明"发任务 → Add a Photo"的路径,或附 iPhone 录屏。

### 🔁 Guideline 2.3.6 — 未声明 "Messaging and Chat" [纯元数据]
- App 有聊天(`ChatView`/`MessagesView`)。App Store Connect → App Information → Age Rating → **Messaging and Chat = Yes**。无需改代码、无需新包。

### 🔁 Guideline 2.3.6 — 未声明 "User-Generated Content" [纯元数据]
- 用户发任务/资料即 UGC。Age Rating → **User-Generated Content = Yes**。与 1.2 配套。

---

## 自查清单其余项(实测 + 静态)

**通过 ✅**
- 隐私政策/条款:启动即弹同意页含 Privacy Policy + Terms 链接;Profile→Settings 内也有 WebView 入口(5.1.1)
- 账号删除:`ProfileView` 有 "Delete Account" + 二次确认 → `DELETE /users/me`(5.1.1(v))
- 隐私清单:`PrivacyInfo.xcprivacy` 存在,声明 Email/Name 用途、未追踪(5.1)
- 第三方登录替代:同时提供 email 与 Sign in with Apple,满足 4.8
- 相机用途串 `NSCameraUsageDescription` 存在(2.5)
- 游客可浏览,后端在线,任务流加载正常(2.1)

**风险 / 待办 ⚠️**
- **2.4.1 / 设计**:纯 iPhone 应用在 iPad 上是居中缩放窗口(左右露 iPad 壁纸)。合规但体验差,且正是 bug 温床 —— 建议正式适配 iPad。
- **无障碍**:底部 Tab Bar(Tasks/Messages/Me)在 accessibility 树里是单个 "Tab Bar" group,各 tab 未暴露独立 label —— VoiceOver 体验受损,建议给每个 tab 加 `.accessibilityLabel`。
- **demo 账号**:务必在 App Review Information 填 email+password 测试账号(2.1 最常见二次被拒原因)。

---

## 优先级建议

1. **【必做·阻断】修复 iPad 模态弹窗** —— 首选 `TARGETED_DEVICE_FAMILY=1,2` 正式支持 iPad 并全流程回归;最低限度也要让兼容模式弹窗可用,并**在 iPad 上亲测**。修好后 2.1a / 2.3 / 1.2 应一并缓解。
2. **【必做·元数据】** Age Rating 勾选 Messaging and Chat = Yes、User-Generated Content = Yes。
3. **【必做·回复】** iPhone 真机录制 block 流程,连同 demo 账号、"Add a Photo" 路径一起写进 App Review 备注并回复 Resolution Center。
4. **【建议】** 适配 iPad 布局、补 Tab Bar 无障碍 label。

---

## 截图

- `axe-audit/01-launch.png` 隐私同意页(iPad)· `02..05` 浏览/任务详情(iPad)
- `axe-audit/06-moderation.png` iPad 点 More **无弹窗** · `08-login.png` iPad 点 Sign In **无弹窗**
- `axe-audit/iphone-03-signin.png` iPhone 登录页**正常**(含 SIWA)· `iphone-04-moderation.png` iPhone 审核弹窗**正常**
