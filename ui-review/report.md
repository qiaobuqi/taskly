# Taskly iOS — 界面功能验收 & 设计规范检查报告

**设备:** iPhone 16 Pro 模拟器 (402×874 pt, iOS 26 / Xcode 26) · **构建:** Taskly scheme, Debug
**日期:** 2026-05-30 · **联调环境:** 本地 Go 后端 `:8080` + PostgreSQL 16,客户端 `DEBUG` 指向 `http://localhost:8080/v1`
**工具:** AXe v1.7.0(accessibility 驱动:describe-ui / tap / type / screenshot) + 前后端请求日志
**走查范围:** 邮箱注册/登录 → 任务列表 → 发布任务 → 任务详情 → 消息 → 我的(Profile)

---

## 概要

整体 UI 质量不错,基本符合 iOS 原生设计规范:卡片、空状态、表单分组、Tab 栏、详情页都比较干净。
但通过前后端联调,**发现并修复了 2 个会直接阻断核心流程的严重 bug**(第 2 个邮箱用户无法注册、
登录成功却卡在登录页),以及若干功能/无障碍/规范问题。修复后,「注册 → 登录 → 发布任务 → 查看详情」
全链路已跑通。结论:**核心闭环可用,但上线前需处理下面列出的功能与无障碍问题。**

---

## 一、联调中发现并已修复的 Bug

### ❌ [严重] 第 2 个邮箱用户注册必失败 — 已修(后端)
- **现象:** 应用内注册返回 `500 create user failed`。日志定位:
  `duplicate key value violates unique constraint "idx_users_apple_user_id"`。
- **根因:** `users.apple_user_id` 与 `users.email` 都是普通 `uniqueIndex`。邮箱注册时
  `apple_user_id` 是空字符串 `""`;第二个邮箱用户又插入 `""` → 唯一约束冲突。(Apple 登录用户
  若不返回邮箱,`email=""` 也会同样崩。)
- **修复:** 改为**部分唯一索引**(仅当值非空且未软删时唯一)。见
  `taskly-server/internal/database/database.go`(`autoMigrate` 末尾)+ `models.go` 去掉 `uniqueIndex` tag。
- **影响:** 这是阻断性问题 —— 没有它,平台第二个邮箱用户就注册不了。

### ❌ [严重] 登录/注册成功但客户端解码失败,卡在登录页 — 已修(客户端)
- **现象:** 服务端 `POST /auth/login` 返回 `200` + 有效 token,但 App 报
  "Response could not be decoded… data is missing",用户停留在登录页。
- **根因:** `NetworkManager` 的 `JSONDecoder` 同时设置了 `keyDecodingStrategy = .convertFromSnakeCase`
  **和**模型里显式的 snake_case `CodingKeys`(如 `skillTags = "skill_tags"`)。两者互斥:
  `convertFromSnakeCase` 先把 `skill_tags` 改写成 `skillTags`,再去匹配 raw value 为 `"skill_tags"`
  的 key → 匹配不上 → 必填字段 `created_at` "缺失" → **所有接口解码全部失败**。
- **修复:** 移除 `.convertFromSnakeCase`,以模型自带的显式 `CodingKeys` 为唯一映射来源。
  (已确认 `Conversation` 非 Codable、`/messages/conversations` 解码为 `[User]`,移除后无副作用。)

### ⚠️ 时间戳带小数秒导致日期解析失败 — 已预防性修复(客户端)
- 后端返回 RFC3339 带小数秒(`...728649+08:00`),Swift 的 `.iso8601` 策略不支持小数秒。
- **修复:** `NetworkManager` 改用自定义日期解码,先试「含小数秒」格式再回退普通 ISO8601。

---

## 二、功能验收发现(建议处理)

| 级别 | 页面 | 问题 | 建议 |
|---|---|---|---|
| ⚠️ | 任务列表 | **发布任务后列表不自动刷新**,需切到别的 Tab 再切回才显示。PostTaskView 是 sheet,关闭不触发 board 的 `.task` 重载。 | 发布成功后通过通知/共享状态触发 `vm.load()`,或在 Tasks Tab 重新出现时刷新。 |
| ⚠️ | 登录/注册 | **错误提示是 Alamofire 原始英文**(如 "Response status code was unacceptable: 500."),而非服务端返回的 `message`。因为 `.validate()` 在解码 body 前就失败。 | 在 NetworkManager 失败分支里解析响应 body 的 `{code,message}`,抛出带服务端 message 的业务错误。 |
| ⚠️ | 发布任务 | **Address 为必填但无任何提示**:Title 或 Address 为空时 Post 按钮一直灰(`disabled(... \|\| vm.address.isEmpty)`),用户不知为何点不了。 | 必填项加标注(`*`/"必填"),或把 Address 设为可选,或在按钮旁提示缺什么。 |
| ✅ 已改进 | 任务列表 | 卡片由 `.onTapGesture` 改为 `Button` 包裹。导航本身是通的(我此前是点到了卡片下方空白处),但 List 行用 `.onTapGesture` 不可靠,且改 Button 后整张卡成为单个带标签的无障碍元素。 | 已应用。 |

> 走通的功能:邮箱注册、邮箱登录、会话恢复、任务列表加载、发布任务(含分类/预算/地址)、
> 任务详情(GET 详情 + 申请列表)、消息空状态、个人页(stats / 我的任务 / 我的接单)。

---

## 三、设计规范 / 无障碍(HIG)

### 无障碍(建议优先,影响 VoiceOver 用户)
- ⚠️ **输入框无 accessibility label**:Email / Password / Title / Description / Address 等
  `describe-ui` 里 `AXLabel` 均为 `null`,仅 placeholder 作 value。建议加 `.accessibilityLabel(...)`。
- ⚠️ **设置按钮 label 是 "gearshape"**(直接是 SF Symbol 名)。Profile 右上角齿轮应给
  `.accessibilityLabel("设置")`。
- ⚠️ **底部 Tab Bar 子项未单独暴露**:`describe-ui` 中是一个 `Group "Tab Bar"`,无法逐项读到
  Tasks/Post/Messages/Me。需确认 VoiceOver 下可逐项聚焦(SwiftUI TabView 通常可以,但这里被合并了,值得复查)。

### 触控区 / 布局
- ⚠️ **文本输入框高度仅 34pt**(登录、注册、发布表单),低于 44pt 最小触控区。Sign In / Create Account
  / Apple 按钮为 50pt,合格。
- ✅ 内容均在安全区内,适配灵动岛与底部 home indicator;边距统一(16pt)。
- ✅ 已补 `UILaunchScreen`(原 Info.plist 缺失,会导致新机型 letterbox 非全屏;已加空 dict 修复)。

### 文案 / 细节
- ⚠️ **"1 tasks" 单复数**:数量为 1 时应为 "1 task"。
- ⚠️ **Post 选择器为居中浮层**("Post a Task / Offer a Service"),非 iOS 标准的底部 action sheet。
  建议确认是否有意为之;若想更原生,用 `.confirmationDialog`。

### 做得好的地方(✅)
- 登录页:logo + 标题 + 表单 + 分隔线 + Apple 登录,层次清晰、留白舒适。
- 任务卡片:分类 chip、Open 状态色、定位图标、价格高亮、发布者+评分,信息密度合适。
- 发布表单:标准 iOS 分组 Form(Task Info / Budget & Time / Location),Cancel/Post 导航规范。
- 空状态:任务列表、消息页都有图标 + 主副文案 + 引导(如 "Apply for a task to start chatting")。
- 任务详情:返回 + 更多菜单 + 状态徽章 + 发布者卡片 + 申请列表,且对自己的任务不显示 Apply(逻辑正确)。

---

## 四、修改清单(本次联调改动)

**后端 `taskly-server`**
- `internal/database/database.go` — email / apple_user_id 改为部分唯一索引(修复注册崩溃)。
- `internal/models/models.go` — 去掉两列的 `uniqueIndex` tag。
- `internal/middleware/requestlog.go`(新增)+ `cmd/main.go` — 请求/响应 body 日志中间件(联调用)。

**客户端 `taskly-ios`**
- `Core/Network/NetworkManager.swift` — 移除 `.convertFromSnakeCase`(修复解码);自定义日期解码兼容小数秒;
  `DEBUG` 下 baseURL 指向 `localhost:8080`;新增 `NetworkLogger` EventMonitor(联调日志)。
- `Sources/Taskly/Info.plist` — 加 localhost ATS 例外 + `UILaunchScreen`。
- `Features/Tasks/Views/TaskBoardView.swift` — 任务/服务卡片改 `Button` 包裹(可靠点击 + 无障碍)。

---

## 五、如何复现联调环境

```bash
# 1. 启 PostgreSQL,建库(首次)
brew services start postgresql@16
/opt/homebrew/opt/postgresql@16/bin/createdb taskly_dev

# 2. 启后端(:8080,带联调日志)
cd taskly-server && CONFIG_FILE=configs/config.yaml go run ./cmd

# 3. 跑 iOS(自动找 scheme、启模拟器、编译、装、启动)
cd taskly-ios && ~/.agents/skills/ios-ui-inspector/scripts/build_and_run.sh
```

测试账号(已注册):`walker@example.com` / `Password123`。

---

## 优先级建议

1. **(已修)** 注册唯一索引崩溃 + 客户端解码失败 —— 二者任一不修,App 完全不可用。
2. 发布后列表不刷新 + 错误提示英文化 + 必填项无提示 —— 直接影响核心体验,建议尽快修。
3. 无障碍三项(输入框 label、设置按钮 label、Tab 项暴露)+ 输入框触控区 44pt + "1 task" 单复数 —— 打磨项。
