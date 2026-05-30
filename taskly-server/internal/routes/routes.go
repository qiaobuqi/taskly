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
	upload := handlers.NewUploadHandler()

	v1 := r.Group("/v1")

	// ── Public ──────────────────────────────────────────────────────────────
	v1.POST("/auth/register", auth.Register)
	v1.POST("/auth/login", auth.Login)
	v1.POST("/auth/apple", auth.AppleLogin)
	v1.POST("/payments/webhook", payment.Webhook)

	// ── Authenticated ────────────────────────────────────────────────────────
	api := v1.Group("", middleware.AuthRequired())

	// Upload
	api.POST("/upload/image", upload.Image)

	// Users
	api.GET("/users/me", user.GetMe)
	api.PUT("/users/me", user.UpdateMe)
	api.GET("/users/me/tasks", user.GetMyTasks)
	api.GET("/users/me/jobs", user.GetMyJobs)
	api.GET("/users/me/verification", user.GetVerification)
	api.POST("/users/me/verification", user.SubmitVerification)
	api.GET("/users/:id", user.GetUser)
	api.GET("/users/:id/reviews", review.GetUserReviews)

	// Wallet
	api.GET("/wallet", user.GetWallet)
	api.POST("/wallet/withdraw", user.Withdraw)

	// Tasks
	api.GET("/tasks", task.List)
	api.POST("/tasks", task.Create)
	api.GET("/tasks/:id", task.Get)
	api.POST("/tasks/:id/apply", task.Apply)
	api.GET("/tasks/:id/applications", task.GetApplications)
	api.POST("/tasks/:id/applications/:appId/accept", task.AcceptApplication)
	api.POST("/tasks/:id/complete", task.MarkComplete)
	api.POST("/tasks/:id/confirm", task.ConfirmCompletion)

	// Services
	api.GET("/services", service.List)
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

	// ── Admin ────────────────────────────────────────────────────────────────
	admin := v1.Group("/admin", middleware.AuthRequired())
	admin.GET("/verifications", handlers.AdminListVerifications)
	admin.POST("/verifications/:id/approve", handlers.AdminApproveVerification)
	admin.POST("/verifications/:id/reject", handlers.AdminRejectVerification)
}
