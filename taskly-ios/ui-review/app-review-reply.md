# Taskly — App Review 提交文案(Submission 4edf420a 重提)

> 提交前替换所有 `「…」` 占位符。Reviewer 看英文,正文保持英文。

---

## A. App Review Information → Notes(随新构建一起填)

```
Thank you for reviewing Taskly.

DEMO ACCOUNT (email + password login — no SMS/OTP required):
  Email:    appreview@taskly.app
  Password: Review2026!
This account has full access to all features.

WHAT WAS FIXED SINCE THE LAST SUBMISSION (4edf420a):
The previous build was an iPhone-only app and was reviewed on iPad, where
it ran in iPhone compatibility mode. In that mode all modal sheets failed
to present, which made the Sign in with Apple screen, the task-posting
flow, and the Report/Block sheet appear "unresponsive" or "missing." We
have made Taskly a Universal app (iPhone + iPad) and verified on an iPad
Air 11" (M3) that every flow below now works.

HOW TO REACH KEY FEATURES:
• Sign in with Apple — Open the "Me" tab → tap "Sign In" → the login sheet
  shows Email/Password and a "Sign in with Apple" button.
• Add a Photo when posting a task — Sign in → tap "+ Post a task or
  service" → "Post a task" → scroll to the "Add a Photo" picker (up to 6
  photos).
• Report / Block a user (Guideline 1.2) — Open any task → tap the "⋯" (More)
  button at the top right → "Report this user" / "Block this user".
  Blocking hides that user's content immediately and files a report to us;
  we act on reports within 24 hours.

AGE RATING: We have updated the Age Rating questionnaire to declare
"Messaging and Chat = Yes" and "User-Generated Content = Yes".

A screen recording of the Block flow (captured on a physical device) is
attached in our Resolution Center reply.

Thank you.
```

---

## B. Resolution Center 回复(逐条回应 5 个问题)

```
Hello, and thank you for the detailed feedback. We have addressed every
item from the previous review. Summary below.

ROOT CAUSE (covers 2.1(a), 2.3, and 1.2):
The prior build was iPhone-only and, when reviewed on iPad, ran in iPhone
compatibility mode where modal sheets did not present. This single issue
made several features look broken or missing. Taskly is now a Universal
app and we re-tested all flows on an iPad Air 11" (M3).

— Guideline 2.1(a), Sign in with Apple unresponsive —
Fixed. The login screen (which contains Sign in with Apple) is presented
as a sheet that previously would not open on iPad. With Universal support
the login sheet now presents correctly and the Sign in with Apple button
is fully functional. Steps: "Me" tab → "Sign In".

— Guideline 2.3, "Add a Photo" not found —
The feature exists. Posting a task requires sign-in, and because the login
sheet would not open on iPad the reviewer could not reach the posting
screen. With the fix above, sign in → "+ Post a task or service" → "Post a
task" → the "Add a Photo" picker (up to 6 photos) is visible. A demo
account is provided in App Review Information.

— Guideline 1.2, User-Generated Content moderation —
Taskly includes the full moderation suite: content reporting, user
blocking (which instantly removes the blocked user's content from the
reporter's feed and notifies us), a zero-tolerance EULA, and a process to
remove objectionable content and eject offending users within 24 hours.
This was already implemented; the Report/Block sheet simply would not open
on iPad before. It now works. A screen recording of the Block flow,
captured on a physical device, is attached. Steps: open any task → "⋯" →
"Block this user".

— Guideline 2.3.6, Messaging and Chat / User-Generated Content —
We have updated the Age Rating questionnaire to answer "Yes" to both
"Messaging and Chat" and "User-Generated Content".

We have provided a working email/password demo account in App Review
Information. Please let us know if anything else is needed. Thank you.
```

---

## 提交前自查
- [ ] demo 账号填好真实可登录的 email+password(别用 OTP/手机号登录)
- [ ] Age Rating:Messaging and Chat = Yes、User-Generated Content = Yes
- [ ] iPhone 真机录 block 流程的视频已附到 Resolution Center
- [ ] 新构建已包含 `TARGETED_DEVICE_FAMILY=1,2`,build 号已递增
