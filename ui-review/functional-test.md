# Taskly 全功能测试报告(MySQL 后端)

**日期:** 2026-05-31 · **后端:** Go + MySQL(本地 `taskly` 库)· **客户端:** iOS 模拟器(绿色重设计版)
**方式:** AXe 驱动模拟器 + API 直测多用户流程(单模拟器难覆盖双人流程,用 curl 补全)

## 功能测试矩阵

| 功能 | 结果 | 说明 |
|---|---|---|
| 邮箱注册 | ✅ | 多用户注册成功;重复邮箱 409;空 apple_user_id 不再冲突(MySQL 应用层去重) |
| 邮箱登录 / 会话恢复 | ✅ | 模拟器登录 m1,加载 MySQL 数据 |
| 任务列表 / 分类筛选 / 排序 | ✅ | 列表从 MySQL 加载,绿色卡片 + 状态胶囊正常 |
| 发布任务 | ✅ | 含分类/预算/地址;发布后列表**自动刷新**(已修);必填项有提示(已修) |
| 任务详情 | ✅ | GET 详情 + 申请列表;自己开放任务无底部按钮 |
| 申请任务 | ✅ | **需先实名认证**(产品规则);报价+留言 |
| 查看/接受申请 | ✅ | 接受后任务 → `in_progress`,assignee 正确 |
| 任务状态机 | ✅ | open → in_progress 验证通过(模拟器可见 "In Progress") |
| 实名认证提交 | ✅ | real_name/document_type/front_image |
| 管理员审核实名 | ⚠️ | 通过,但**端点未做管理员鉴权**(见严重问题) |
| 服务卡发布/列表 | ✅ | StringArray(skill_tags/images)JSON 列读写正常 |
| 消息 | ✅(空态) | 会话列表空态;实时 WS 未单测 |
| 个人页 / 我的任务/接单 | ✅ | M1 Profile 显示 in_progress 任务 |
| 数据埋点 | ✅ | ingest + DAU + 留存(MySQL CTE)全通,事件入库带 user_id |
| **支付流程** | 🔴 **阻塞** | 链路全对,卡在 Stripe:`Invalid API Key provided: sk_test_...`(占位密钥) |
| **短信** | 🔴 **未实现** | 代码中无任何 SMS/短信/验证码功能 |

## 三个必须处理的问题

### 🔴 1. 支付:缺真实 Stripe 测试密钥
`create-intent` 一路走到调用 Stripe,返回:
```
500 stripe error: Invalid API Key provided: sk_test_...
```
代码无误,**只需在 config 填真实 `sk_test_` / `pk_test_` 密钥**即可跑通担保支付。客户端 `PaymentView` 用 StripePaymentSheet,publishable key 也要一并配。

### 🔴 2. 短信:功能不存在
全仓库无 sms / 短信 / phone / 验证码 / Twilio / 阿里云短信。当前认证 = 邮箱 + Apple。
若产品需要短信登录/验证码,这是一个**新功能**(需接短信服务商 + 手机号字段 + 验证码下发/校验流程),不是「调通」问题。

### 🔴 3. 安全:管理员端点未鉴权
`/v1/admin/*`(审核/封禁实名)只用 `AuthRequired()`,**任何登录用户都能调用**——本次测试里普通用户 m1 就批准了 m2 的实名。上线前必须加管理员角色校验(如 user.role / 白名单)。

## 已确认正常(本轮新建/修复回归)
- Postgres → MySQL 迁移:驱动/DSN、JSON 数组列、应用层去重、埋点 SQL 全部本地跑通。
- 绿色重设计 + TasklyLogo 在真机渲染正常。
- 发布后自动刷新、错误提示用服务端 message、必填项提示——回归通过。
