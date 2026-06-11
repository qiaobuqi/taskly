---
name: ios-device-debug
description: >-
  Field-debugging playbook for iOS apps misbehaving on REAL devices and in App
  Review, distilled from hard-won Taskly incidents. Use this skill whenever the
  user reports: black screen / blank screen at launch (真机黑屏, 启动黑屏),
  launch screen not showing or "LaunchScreen.storyboard 没创建", an app that is
  slow to open on device, infinite loading spinners (一直 loading / 转圈),
  login stuck or "Sign in with Apple" unresponsive / 未能完成登录, TLS or
  network errors in device logs (-1200, -9816, nw_endpoint_flow_failed,
  127.0.0.1 proxy connections), requests hanging forever, or an App Store
  rejection that needs forensic diagnosis (审核被拒, Guideline 2.1 / 2.3).
  Consult it BEFORE guessing — it encodes the correct diagnosis order and the
  exact commands, and most of these symptoms have counter-intuitive root causes.
---

# iOS Device Debug Playbook

Lessons from real incidents (Taskly, 2026-06): every symptom below was misdiagnosed
at least once before the true cause was found. Follow the diagnosis order — it is
ordered by "cheapest decisive evidence first", not by plausibility.

## 0. First rule: confirm WHICH build is actually running

Half of all "the fix didn't work" reports are the device running a stale build.
Before re-investigating anything:

- Look for the build's startup marker in console (Taskly prints
  `🛡 [NET] NetworkManager up — baseURL=…, proxy bypass ACTIVE` in DEBUG).
  If your app has no such marker, add one — a single `print` at init that names
  the feature you just shipped.
- Absence of NEW telemetry is evidence too: if you added an analytics event and
  it never arrives while older events do, the build predates your change.
- Launch screens are snapshot-cached by iOS: after changing launch screen config,
  DELETE the app and reinstall (occasionally reboot) or you'll see the old screen
  and wrongly conclude the change "wasn't added".

## 1. Black screen at launch (真机黑屏)

Cause in practice: **no usable launch screen**. `UILaunchScreen: {}` (empty dict)
in Info.plist renders as a black screen on device for the whole cold start
(1–2 s with big SDKs like Stripe). Simulator hides this; device shows it.

Fix options (pick ONE — they are mutually exclusive):
- `UILaunchScreen` dict with `UIColorName` (+ optional `UIImageName`) — modern, no file.
- `UILaunchStoryboardName: LaunchScreen` + a real `LaunchScreen.storyboard` —
  what users usually expect when they ask "launch screen 文件呢?". Storyboard can
  reference asset-catalog named colors (auto dark mode) and a centered logo imageset.

With xcodegen: new .storyboard files need `xcodegen generate` to enter the pbxproj;
new content INSIDE an `.xcassets` does not. Update `project.yml` AND `Info.plist`
together or the next generate silently reverts your plist edit.

Verify the artifact, never just the source:
```bash
plutil -p <app>/Info.plist | grep -i launch          # key present?
ls <app> | grep -i launch                            # storyboardc compiled in?
xcrun assetutil --info <app>/Assets.car | grep <Name> # color/image in catalog?
codesign -d --entitlements :- <app>                  # entitlements really embedded?
```

## 2. Requests hang forever / infinite spinners (一直 loading)

Two independent causes, both usually present:

**a. `waitsForConnectivity = true` without a resource timeout.** The 30 s
`timeoutIntervalForRequest` does NOT apply while "waiting for connectivity";
the real cap is `timeoutIntervalForResource` (default: 7 days). Any
no-connectivity state (cellular-permission prompt not yet answered on
China-market iPhones, network transitions) hangs every request indefinitely.
Fix: keep `waitsForConnectivity` (it gracefully survives the China permission
prompt) but set `timeoutIntervalForResource` to ~20 s.

**b. Views that fire requests for logged-out users.** A guest tab that loads
data anyway paints a spinner over the sign-in prompt. Use
`.task(id: authManager.isLoggedIn)` + guard, and gate loading overlays on login
state. Bonus: keying on login state auto-reloads after login.

Map opaque URLErrors to readable messages (timeout / offline) — Alamofire's raw
"sessionTaskFailed" text reads as a bug to users and reviewers.

## 3. TLS failures through a local proxy (the -9816 fingerprint)

Console signature:
```
nw_endpoint_flow_failed_with_error [... 127.0.0.1:<port> ... interface: lo0]
Code=-1200 "A TLS error caused the secure connection to fail." (-9816)
```
`127.0.0.1:<port>` means a LOCAL proxy (Clash/Shadowrocket/V2Ray family) is
intercepting — on the Mac for simulator runs, on the phone itself for device
runs. The user saying "我没开 VPN" does not rule it out: proxy apps can install
proxies without the VPN badge showing.

If the backend is reachable directly (verify: `curl` it, and from an overseas
vantage point too), bypass proxies for your own traffic. **Both knobs, every
session:**
```swift
config.connectionProxyDictionary = [:]   // classic system proxies
config.proxyConfigurations = []          // iOS 17 NetworkExtension proxies (ignore the dict!)
```
Audit ALL network surfaces — fixing one is not enough. Typical inventory:
Alamofire `Session`, any raw `URLSession.shared` user (analytics!), Kingfisher
(`ImageDownloader.default.sessionConfiguration`), SwiftUI `AsyncImage` (uses
`URLSession.shared`; prefer Kingfisher).

## 4. Sign in with Apple "unresponsive" / 未能完成登录

Decision tree — gather evidence in this order:

1. **Server logs: did `/auth/apple` ever arrive?**
   `journalctl -u <service> --since … | grep auth/apple`
   - Arrived with 4xx/5xx → server-side; read the handler.
   - Never arrived while other requests from the same device succeed → the
     failure is on-device, BEFORE the network call.
2. **Whose alert is it?** "未能完成登录 / Sign-In Not Completed" is the iOS
   SYSTEM alert → authorization failed inside Apple's flow; your code never got
   a token. Your own alert (give it a distinct title) → error reached your code.
3. **Client black box.** Track every failure path of the Apple flow as an
   analytics event with `stage` (authorization / credential / backend), NSError
   `domain`+`code`, and the FIRST UNDERLYING error (`NSUnderlyingErrorKey` —
   the real cause, e.g. AKAuthenticationError, hides 1–2 levels deep), and
   flush immediately. This is the only way to see errors from devices you can't
   attach to (App Review!). In DEBUG also print the full underlying-error chain.
4. **Known on-device causes** when authorization itself fails: local proxy/VPN
   breaking TLS to `appleid.apple.com` (see §3), device not signed into iCloud,
   stale build (§0). App Store region/territory availability is IRRELEVANT to
   SIWA; so is the Apple ID's country.
5. Entitlement sanity (one-time): `com.apple.developer.applesignin` must appear
   in `codesign -d --entitlements` of the BUILT app, not just in the source files.

UX hardening so it can never look "unresponsive": loading overlay on the button
while the backend call runs, and a prominent `.alert` on failure that suggests
the email fallback. Silent or caption-sized errors get apps rejected (2.1).

## 5. App Review rejection forensics (审核取证)

The rejection text is a SYMPTOM report. Your server logs are the ground truth —
reviewers' devices hit your production API and their IPs identify them
(Apple uses `17.x.x.x`; review infra also appears from other ranges, e.g.
`139.178.x.x` — match by date + behavior).

```bash
# What did the reviewer actually do, with status codes:
journalctl -u <svc> --since "<review date -1d>" --no-pager | grep "\[GIN\]" \
  | grep -E "17\.|<other-ip>" | awk '{print $6,$7,$9,$11,$(NF-3),$(NF-1),$NF}'
# Endpoint/IP frequency overview:
... | awk '{print $(NF-1), $NF, $(NF-3)}' | sort | uniq -c | sort -rn
```

Read the trail like a session replay: what they browsed, where they got 4xx,
what they never reached. Patterns seen in practice:
- "Feature X not found" (2.3) usually means **the reviewer never got past the
  step before it** (e.g. login failed → never saw the post-task screen). Fix the
  blocker, then REPLY with the exact path to the feature + demo account.
- Repeated 400s on auth endpoints = reviewer submitting empty/invalid forms and
  seeing raw validator errors. Add client-side validation with human messages.
- Two rejection reasons are often one root cause. Diagnose before dividing.
- Check reachability from ABROAD (reviewers are in the US; China-hosted servers
  need verification from an overseas vantage), not just from your desk.

Reply ammunition: server-side evidence ("our logs show zero /auth/apple requests
from the review session while其他 requests succeeded") is far more persuasive
than "cannot reproduce".

## 6. Apple-login / network change checklist (before resubmitting)

- [ ] Startup build-marker line present in console
- [ ] All sessions have both proxy-bypass knobs + resource timeout
- [ ] Apple login: loading state, loud alert, staged analytics with underlying error
- [ ] Entitlements verified in built artifact
- [ ] Launch screen verified in built artifact; app deleted & reinstalled on device
- [ ] Demo account works (curl the login endpoint with its credentials)
- [ ] API reachable from overseas vantage point
- [ ] Resolution Center reply drafted with log evidence + exact feature paths
