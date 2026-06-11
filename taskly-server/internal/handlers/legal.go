package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// Privacy policy + terms served as public HTML pages. App Store Connect requires a
// reachable privacy-policy URL (Guideline 5.1.2); these live at
// https://taskly.cnirv.com/privacy and /terms via nginx → this server.

const privacyHTML = `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Taskly Privacy Policy</title>
<style>body{font:16px/1.6 -apple-system,system-ui,sans-serif;max-width:720px;margin:40px auto;padding:0 20px;color:#1a1d1b}h1{font-size:28px}h2{font-size:19px;margin-top:28px}a{color:#1e9e5a}</style></head><body>
<h1>Taskly Privacy Policy</h1>
<p>Last updated: 2026-05-31</p>
<p>Taskly ("we") operates a local task and service marketplace. This policy explains what we collect and how we use it.</p>
<h2>Information we collect</h2>
<ul>
<li><b>Account</b>: email address, nickname, and (if you provide it) avatar and bio.</li>
<li><b>Content you create</b>: tasks, services, applications, messages, and reviews, including the task addresses you type in.</li>
<li><b>Identity verification (optional)</b>: if you choose to verify your identity, we collect your legal name and photos of a government-issued document (passport, national ID, or driver's licence). These are used solely to confirm your identity, are not shown to other users, and can be removed by deleting your account.</li>
<li><b>Payments</b>: processed by Stripe. We do not store full card numbers; Stripe handles card data.</li>
<li><b>Usage analytics</b>: in-app events (e.g. screen views, sign-ups) used to improve the product. This is first-party and not used to track you across other apps or websites.</li>
</ul>
<h2>How we use it</h2>
<p>To provide the service (matching task posters and taskers), process escrow payments, enable messaging, prevent fraud, and improve the app.</p>
<h2>Sharing</h2>
<p>We share payment data with Stripe to process transactions, and task/profile details with other users as needed to fulfil a task. We do not sell your personal data.</p>
<h2>Retention &amp; your rights</h2>
<p>You can delete your account at any time in the app (Profile → Settings → Delete Account), which removes your personal data. You may also contact us to access or correct your data.</p>
<h2>Contact</h2>
<p>Email: <a href="mailto:support@cnirv.com">support@cnirv.com</a></p>
</body></html>`

const termsHTML = `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Taskly Terms of Service</title>
<style>body{font:16px/1.6 -apple-system,system-ui,sans-serif;max-width:720px;margin:40px auto;padding:0 20px;color:#1a1d1b}h1{font-size:28px}h2{font-size:19px;margin-top:28px}a{color:#1e9e5a}</style></head><body>
<h1>Taskly Terms of Service</h1>
<p>Last updated: 2026-05-31</p>
<p>By using Taskly you agree to these terms.</p>
<h2>The service</h2>
<p>Taskly connects people who need tasks done with people who can do them. Payments for tasks are held in escrow and released to the tasker after the poster confirms completion.</p>
<h2>Your responsibilities</h2>
<p>Provide accurate information, perform tasks lawfully and safely, and treat other users respectfully. You are responsible for the tasks you post and accept.</p>
<h2>Payments</h2>
<p>Payments are processed by Stripe. Funds are escrowed at payment and released on confirmation or automatic release. Commission, if any, is shown before payment.</p>
<h2>Prohibited use</h2>
<p>No illegal, harmful, fraudulent, or abusive activity. We may suspend accounts that violate these terms.</p>
<h2>Disclaimer</h2>
<p>Taskly is a marketplace and is not a party to agreements between users. Use the service at your own risk.</p>
<h2>Contact</h2>
<p>Email: <a href="mailto:support@cnirv.com">support@cnirv.com</a></p>
</body></html>`

const supportHTML = `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Taskly Support</title>
<style>body{font:16px/1.6 -apple-system,system-ui,sans-serif;max-width:720px;margin:40px auto;padding:0 20px;color:#1a1d1b}h1{font-size:28px}h2{font-size:19px;margin-top:28px}a{color:#1e9e5a}</style></head><body>
<h1>Taskly Support</h1>
<p>Taskly is a local task and service marketplace. Need help? We're happy to assist.</p>
<h2>Contact us</h2>
<p>Email: <a href="mailto:support@cnirv.com">support@cnirv.com</a><br>We aim to reply within 1–2 business days.</p>
<h2>Common questions</h2>
<ul>
<li><b>How do payments work?</b> Payment for a task is held securely in escrow and released to the tasker after you confirm the work is done.</li>
<li><b>How do I get paid?</b> Earnings appear in your in-app Wallet and can be withdrawn from there.</li>
<li><b>How do I delete my account?</b> Open Profile → Settings (gear icon) → Delete Account. This permanently removes your account and personal data.</li>
<li><b>Identity verification</b> is optional and only used to add a Verified badge to your profile.</li>
</ul>
<h2>Legal</h2>
<p><a href="/privacy">Privacy Policy</a> · <a href="/terms">Terms of Service</a></p>
</body></html>`

func PrivacyPage(c *gin.Context) {
	c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(privacyHTML))
}

func TermsPage(c *gin.Context) {
	c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(termsHTML))
}

func SupportPage(c *gin.Context) {
	c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(supportHTML))
}
