package routes

import (
	"taskly-server/internal/handlers"
	"taskly-server/internal/middleware"

	"github.com/gin-gonic/gin"
)

func Setup(r *gin.Engine) {
	auth := handlers.NewAuthHandler()
	user := handlers.NewUserHandler()
	task := handlers.NewTaskHandler()
	service := handlers.NewServiceHandler()
	message := handlers.NewMessageHandler()
	payment := handlers.NewPaymentHandler()
	review := handlers.NewReviewHandler()
	report := handlers.NewReportHandler()
	block := handlers.NewBlockHandler()
	upload := handlers.NewUploadHandler()
	analytics := handlers.NewAnalyticsHandler()

	v1 := r.Group("/v1")

	// ── Public ──────────────────────────────────────────────────────────────
	// Health probe for load balancers / deploy health checks (no auth, no DB write).
	v1.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})
	// Public legal pages (App Store privacy-policy URL requirement). Served at /v1/...
	// and also at root /privacy, /terms for a clean public URL.
	v1.GET("/privacy", handlers.PrivacyPage)
	v1.GET("/terms", handlers.TermsPage)
	v1.GET("/support", handlers.SupportPage)
	r.GET("/privacy", handlers.PrivacyPage)
	r.GET("/terms", handlers.TermsPage)
	r.GET("/support", handlers.SupportPage)
	v1.POST("/auth/send-code", auth.SendCode)
	v1.POST("/auth/register", auth.Register)
	v1.POST("/auth/login", auth.Login)
	v1.POST("/auth/apple", auth.AppleLogin)
	v1.POST("/payments/webhook", payment.Webhook)
	// Analytics ingest: optional auth so app_open before sign-in still counts.
	v1.POST("/analytics/events", middleware.OptionalAuth(), analytics.Ingest)

	// ── Public browse (guest mode) ──────────────────────────────────────────
	// Read-only marketplace endpoints stay open so guests can browse before
	// signing in. OptionalAuth attaches the user if a token is present but never
	// rejects. Writes/actions remain in the AuthRequired group below.
	pub := v1.Group("", middleware.OptionalAuth())
	pub.GET("/tasks", task.List)
	pub.GET("/tasks/:id", task.Get)
	pub.GET("/services", service.List)
	pub.GET("/users/:id", user.GetUser)
	pub.GET("/users/:id/reviews", review.GetUserReviews)

	// ── Authenticated ────────────────────────────────────────────────────────
	api := v1.Group("", middleware.AuthRequired())

	// Upload
	api.POST("/upload/image", upload.Image)

	// Users
	api.GET("/users/me", user.GetMe)
	api.PUT("/users/me", user.UpdateMe)
	api.DELETE("/users/me", user.DeleteMe)
	api.GET("/users/me/tasks", user.GetMyTasks)
	api.GET("/users/me/jobs", user.GetMyJobs)
	api.GET("/users/me/verification", user.GetVerification)
	api.POST("/users/me/verification", user.SubmitVerification)

	// Wallet
	api.GET("/wallet", user.GetWallet)
	api.POST("/wallet/withdraw", user.Withdraw)

	// Tasks
	api.POST("/tasks", task.Create)
	api.POST("/tasks/:id/apply", task.Apply)
	api.GET("/tasks/:id/applications", task.GetApplications)
	api.POST("/tasks/:id/applications/:appId/accept", task.AcceptApplication)
	api.POST("/tasks/:id/complete", task.MarkComplete)
	api.POST("/tasks/:id/confirm", task.ConfirmCompletion)

	// Services
	api.POST("/services", service.Create)
	api.DELETE("/services/:id", service.Delete)

	// Messages
	api.GET("/messages/ws", message.WebSocket)
	api.GET("/messages/conversations", message.GetConversations)
	api.GET("/messages/:userId", message.GetMessages)
	api.POST("/messages", message.Send)

	// Payments
	api.POST("/payments/create-intent", payment.CreateIntent)

	// Reviews
	api.POST("/reviews", review.Create)

	// Reports
	api.POST("/reports", report.Create)

	// Blocks (App Store Guideline 1.2 — block abusive users)
	api.POST("/blocks", block.Create)
	api.GET("/blocks", block.List)
	api.DELETE("/blocks/:userId", block.Delete)

	// ── Admin ────────────────────────────────────────────────────────────────
	admin := v1.Group("/admin", middleware.AuthRequired(), middleware.AdminRequired())
	admin.GET("/verifications", handlers.AdminListVerifications)
	admin.POST("/verifications/:id/approve", handlers.AdminApproveVerification)
	admin.POST("/verifications/:id/reject", handlers.AdminRejectVerification)
	// Analytics dashboards (DAU / retention) for validating engagement.
	admin.GET("/analytics/dau", analytics.DAU)
	admin.GET("/analytics/retention", analytics.Retention)
}
