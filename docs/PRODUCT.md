# Taskly — 产品规格(反推版 PRD)

> 仓库里没有现成 PRD,这份文档是从后端路由、数据模型、iOS 页面 + 同类竞品(Airtasker / TaskRabbit / Thumbtack)反推出来的「产品意图」,用作功能验收和后续迭代的标尺。带 ❓ 的是推断、需产品确认的点。

## 一、产品定位
本地**任务/服务双边撮合平台**:需求方发布任务 → 服务方申请/接单 → 平台托管支付(Stripe 担保交易)→ 完成确认放款 → 互评。同时支持服务方主动发布「服务卡片」被需求方浏览。模式最接近 **Airtasker**。

- **需求方(Poster)**:发任务、收申请、选人、付款托管、确认放款、评价。
- **服务方(Tasker)**:浏览任务、申请报价、沟通、完成提交、收款、评价;也可发布服务卡片获客。
- 双重身份:同一用户既能发任务也能接单(Profile 区分 My Tasks / My Jobs)。

## 二、核心功能(基于后端 `/v1` 路由 + 模型)
| 模块 | 能力 | 后端端点 | iOS 页面 |
|---|---|---|---|
| 账号 | 邮箱注册/登录、Apple 登录、会话保持 | `/auth/{register,login,apple}` | LoginView |
| 任务 | 列表(分类/排序)、详情、发布、申请、查看申请、选定、标记完成、确认完成 | `/tasks*` | TaskBoardView / TaskDetailView / PostTaskView |
| 服务卡 | 列表、发布、删除 | `/services*` | TaskBoardView(Services 段)/ PostServiceView |
| 申请 | 报价+留言申请、需求方接受 | `/tasks/:id/apply`,`/applications/:id/accept` | ApplyView / ApplicationsSection |
| 支付 | 创建支付意图(Stripe)、Webhook、担保→放款、自动放款(cron) | `/payments/*` | PaymentView |
| 消息 | 会话列表、历史、发送、WebSocket 实时 | `/messages*` | MessagesView / ChatView |
| 评价 | 任务完成后双向评价、查看用户评价 | `/reviews`,`/users/:id/reviews` | ReviewView |
| 钱包 | 余额、流水、提现 | `/wallet*` | WalletView |
| 实名认证 | 提交证件、状态、管理员审核 | `/users/me/verification`,`/admin/verifications*` | VerificationView |
| 举报 | 举报任务/用户 | `/reports` | confirmationDialog |
| 个人 | 资料、我的任务/接单、设置、登出 | `/users/me*` | ProfileView / SettingsView |

## 三、关键状态机
- **任务状态**:`open → in_progress → pending_confirm → completed`(另有 `cancelled / disputed`)。
  - open:可申请;需求方接受某申请后 → in_progress。
  - in_progress:需求方付款托管;服务方「标记完成」→ pending_confirm。
  - pending_confirm:需求方「确认并放款」→ completed(或自动放款 cron 兜底)。
  - completed:双方可互评。
- **支付**:Stripe PaymentIntent,平台托管;`commission.rate` 早期 0%(后端配置,后续改 10%)。
- **实名**:`none → pending → approved/rejected`,管理员后台审核。

## 四、预期用户主流程(验收基线)
1. **新用户激活**:打开 → 注册(邮箱)→ 浏览任务列表 → 看详情。
2. **发需求**:Post → Post a Task → 填标题/描述/分类/预算/(可选)截止/地址 → 发布 → 列表出现。
3. **接单**:浏览/筛选任务 → 详情 → 申请(报价+留言)→ 沟通 → 被选中 → 完成 → 收款 → 评价。
4. **选人付款**:需求方看申请 → 接受 → 付款托管 → 完成确认 → 放款 → 评价。

## 五、已确认缺失/待补(MVP 视角,detail 见 product-review)
- 🔴 **搜索**:无关键词搜索(竞品标配)。
- 🔴 **任务配图上传**:发布表单无图片上传(模型 `images` 已支持,UI 缺)。
- 🟡 **推送通知**:`device_token` 字段在,但无推送注册/通知中心。
- 🟡 **新手引导 / 空状态 CTA**:空列表无「发布第一个任务」引导。
- 🟡 **地图/距离**:任务有经纬度字段,但列表无「附近」排序/地图视图。
- 🟡 **Reviews 入口**:Profile 的 Reviews 按钮当前空实现。
- ❓ **服务卡详情→下单**:服务卡能浏览,但「直接下单某服务」的闭环未见。

## 六、数据指标(埋点目标)
早期重点验证**留存与日活**,其次激活漏斗:
- DAU/WAU/MAU:`app_open` / `session_start`(带 per-install `anon_id`,登录后并入 `user_id`)。
- 留存:按首次活跃日 cohort 的 D1/D7 回访。
- 激活漏斗:`sign_up → screen_view(tasks) → task_open → post_task_submit / apply_open → pay_open`。
- 详见 `docs/ANALYTICS.md`。
