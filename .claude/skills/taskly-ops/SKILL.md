---
name: taskly-ops
description: >-
  Operational runbook for the Taskly backend: where every config value and secret lives
  (local dev + production server), and how to test the payment flow end-to-end. Use this
  whenever someone asks "where are the Stripe keys / DB password / config", "Taskly 密钥/配置
  在哪", "how do I test payments", "支付流程怎么测", "is payment working", needs to change
  Stripe keys, points the app at a different environment, or is about to deploy/operate the
  Taskly server. Check here first instead of grepping around — it's the source of truth for
  config locations and the payment test recipe.
---

# Taskly Ops

Two things people repeatedly need and otherwise can't find: **where config/secrets live**, and
**how to confirm payments work**. Both are below.

## 1. Where config & secrets live

There are two environments. Each has its own config file; secrets differ.

### Local dev
- **`taskly-server/configs/config.yaml`** — committed to git, holds **dev/placeholder** values:
  local MySQL (`root` / `123456` / db `taskly` on `127.0.0.1:3306`), a dev JWT secret, and
  Stripe keys. Safe to edit. The server reads it by default (or via `CONFIG_FILE` env).
- iOS app in **DEBUG** points at `http://localhost:8080/v1` (`APIConstants.baseURL`, `#if DEBUG`).
- Run locally: `cd taskly-server && CONFIG_FILE=configs/config.yaml go run ./cmd`.

### Production server (`root@47.94.93.24`, alongside ifangche on the same box)
- **`/opt/apps/taskly-server/configs/config.prod.yaml`** — lives **only on the server, never in
  git**. This is the source of truth for prod secrets:
  - DB → Aliyun RDS `rm-bp1lc5ao7288z3c2n5o.mysql.rds.aliyuncs.com:3306`, database `taskly`.
  - `jwt.secret` (randomized), `stripe.secret_key` (`sk_test_…`), `stripe.publishable_key` (`pk_test_…`).
  - `server.port: "8430"`, `mode: release`.
- The systemd unit `taskly-server.service` sets `Environment=CONFIG_FILE=…/config.prod.yaml`,
  so the binary loads this file. Routine deploys (`scp` new binary + restart) **do not touch
  it**, so keys persist across deploys.
- View / edit:
  ```bash
  ssh root@47.94.93.24 'grep -v secret /opt/apps/taskly-server/configs/config.prod.yaml'   # peek (mask secrets)
  ssh root@47.94.93.24 'nano /opt/apps/taskly-server/configs/config.prod.yaml && systemctl restart taskly-server'
  ```
- The iOS app never stores the Stripe publishable key — the server returns it in the
  `create-intent` response, so changing keys is a **server-only** change.

**Security:** real secrets live only in `config.prod.yaml` on the server. Don't paste live keys
into chat or commit them; rotate any test keys before going live (Stripe → roll key).

## 2. Testing the payment flow

Payment is wired through **Stripe** (Apple Pay and card both settle through it). The common
failure mode is a placeholder `sk_test_…` key → `create-intent` returns
`Invalid API Key provided`. To confirm it's actually working, run the bundled script — it walks
the whole lifecycle (the gates matter: applying needs identity verification, paying needs an
in_progress task) and asserts a real PaymentIntent comes back:

```bash
# Local backend:
bash .claude/skills/taskly-ops/scripts/test_payment_flow.sh

# Production (run it on the server so it reaches the RDS + uses prod keys):
ssh root@47.94.93.24 'bash -s' < .claude/skills/taskly-ops/scripts/test_payment_flow.sh http://127.0.0.1:8430/v1
```

A pass looks like: `✅ PASS — real Stripe PaymentIntent: pi_3Tcx...`.

**Test on the server, not locally.** The Stripe test secret key is IP-restricted to the prod
server (`47.94.93.24`), so a local backend's call to Stripe fails with *"API key … does not
allow requests from your IP"*. Since `create-intent` is made by the *server*, testing against
prod is both correct and the only place it works. The committed local `config.yaml` therefore
keeps only placeholder Stripe keys.

**Always mark test data.** Anything created while testing must be obviously fake so it's never
mistaken for a real user/task and is easy to purge: emails on **`@taskly.test`**, and a
**`[TEST]`** prefix on nicknames and task titles. The bundled script already does this.

**Cleaning test data** (removes only the marked rows):
```bash
ssh root@47.94.93.24 'mysql -h rm-bp1lc5ao7288z3c2n5o.mysql.rds.aliyuncs.com -u backend -pMiga0818 taskly -e "
  DELETE FROM tasks WHERE title LIKE \"[TEST]%\";
  DELETE FROM users WHERE email LIKE \"%@taskly.test\";
"'
```

**App-side (the visible part):** in the simulator, open a task you don't own that's `in_progress`
where you're the payer, tap Pay → the Stripe PaymentSheet appears → pay with test card
**`4242 4242 4242 4242`**, any future expiry, any CVC. For the **Apple Pay** button to show in
that sheet you additionally need an Apple Merchant ID (`merchant.com.taskly.app`) + the Apple Pay
capability in `Taskly.entitlements` (currently empty) + the merchant linked in Stripe; without it
the sheet still works for card entry.

## Related
- Deploy mechanics (cross-compile → scp → atomic swap → restart): use the global
  `server-deploy` skill.
- Full-stack local run + DB details: see the project memory `taskly-local-run`.
