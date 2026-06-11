#!/usr/bin/env bash
# Drive Taskly's full payment lifecycle end-to-end and assert create-intent returns a
# real Stripe PaymentIntent. This is the fastest way to confirm "支付流程是通的" after
# changing Stripe keys, deploying, or switching environments.
#
# Usage:
#   test_payment_flow.sh [BASE_URL]
#     BASE_URL defaults to http://127.0.0.1:8080/v1 (local dev).
#     For prod, run it ON the server: ssh root@<server> 'bash -s' < this_script  http://127.0.0.1:8430/v1
#
# Why each step: applying to a task is gated behind identity verification, and paying
# needs an in_progress task with an assignee — so we must walk publisher+worker through
# register → verify → approve → apply → accept before create-intent will succeed.
set -euo pipefail
BASE="${1:-http://127.0.0.1:8430/v1}"   # default = prod loopback; we only test on the server
PASS="Password123"
TS=$(date +%s)
# Test data is deliberately MARKED so it's never confused with real users/tasks:
#  - emails on the @taskly.test domain   - "[TEST]" prefix on nicknames + task titles
# This makes it trivial to spot and clean up (see "Cleaning test data" in SKILL.md).
PUB="test_pub_$TS@taskly.test"; WRK="test_wrk_$TS@taskly.test"

get(){ python3 -c "import sys,json;print(json.load(sys.stdin)$1)"; }
listget(){ python3 -c "import sys,json;d=json.load(sys.stdin)['data'];l=d if isinstance(d,list) else d.get('list',[]);print($1)"; }
reg(){ curl -s -X POST $BASE/auth/register -H 'Content-Type: application/json' -d "{\"email\":\"$1\",\"password\":\"$PASS\",\"nickname\":\"[TEST] $2\"}" >/dev/null; }
tok(){ curl -s -X POST $BASE/auth/login -H 'Content-Type: application/json' -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | get "['data']['token']"; }

echo "→ target: $BASE"
reg "$PUB" Publisher; reg "$WRK" Worker
T1=$(tok "$PUB"); T2=$(tok "$WRK")
TID=$(curl -s -X POST $BASE/tasks -H "Authorization: Bearer $T1" -H 'Content-Type: application/json' \
  -d '{"title":"[TEST] pay flow","description":"automated payment test — safe to delete","category":"other","budget":120,"currency":"USD","address":"SF"}' | get "['data']['id']")
echo "  task #$TID created"
curl -s -X POST $BASE/users/me/verification -H "Authorization: Bearer $T2" -H 'Content-Type: application/json' \
  -d '{"real_name":"W","document_type":"id_card","front_image_url":"http://x/f.jpg"}' >/dev/null
VID=$(curl -s $BASE/admin/verifications -H "Authorization: Bearer $T1" | listget "[x['id'] for x in l if x.get('status')=='pending'][-1]")
curl -s -X POST $BASE/admin/verifications/$VID/approve -H "Authorization: Bearer $T1" -d '{}' >/dev/null
echo "  worker verified"
curl -s -X POST $BASE/tasks/$TID/apply -H "Authorization: Bearer $T2" -H 'Content-Type: application/json' \
  -d '{"message":"me","proposed_price":110}' >/dev/null
APPID=$(curl -s $BASE/tasks/$TID/applications -H "Authorization: Bearer $T1" | listget "l[0]['id']")
curl -s -X POST $BASE/tasks/$TID/applications/$APPID/accept -H "Authorization: Bearer $T1" -d '{}' >/dev/null
echo "  applied + accepted → in_progress"
echo "→ create-intent:"
curl -s -X POST $BASE/payments/create-intent -H "Authorization: Bearer $T1" -H 'Content-Type: application/json' \
  -d "{\"task_id\":$TID}" | python3 -c "
import sys,json
d=json.load(sys.stdin)
cs=(d.get('data') or {}).get('client_secret','') if d.get('code')==200 else ''
if cs.startswith('pi_'):
    print('  ✅ PASS — real Stripe PaymentIntent:', cs[:20]+'...')
else:
    print('  ❌ FAIL —', d.get('code'), d.get('message') or d)
    print('     (placeholder Stripe key? check stripe.secret_key in the active config)')
"
echo "App-side: PaymentSheet then pays with test card 4242 4242 4242 4242, any future expiry, any CVC."