package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"

	"taskly-server/internal/config"
	"taskly-server/internal/database"
	"taskly-server/internal/middleware"
	"taskly-server/internal/models"

	"github.com/gin-gonic/gin"
	"github.com/stripe/stripe-go/v76"
	"github.com/stripe/stripe-go/v76/paymentintent"
	_ "github.com/stripe/stripe-go/v76/refund"
)

type PaymentHandler struct{}

func NewPaymentHandler() *PaymentHandler {
	return &PaymentHandler{}
}

func initStripe() {
	stripe.Key = config.Global.Stripe.SecretKey
}

// POST /v1/payments/create-intent
func (h *PaymentHandler) CreateIntent(c *gin.Context) {
	initStripe()
	uid := middleware.CurrentUserID(c)
	var req struct {
		TaskID uint `json:"task_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}

	var task models.Task
	if database.DB.Preload("Assignee").First(&task, req.TaskID).Error != nil {
		c.JSON(http.StatusNotFound, models.Fail(404, "task not found"))
		return
	}
	if task.PublisherID != uid {
		c.JSON(http.StatusForbidden, models.Fail(403, "only task publisher can pay"))
		return
	}
	if task.AssigneeID == nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, "no assignee yet"))
		return
	}

	// Check no existing payment
	var existingCount int64
	database.DB.Model(&models.Payment{}).
		Where("task_id = ? AND status IN ('escrowed','pending')", task.ID).
		Count(&existingCount)
	if existingCount > 0 {
		c.JSON(http.StatusConflict, models.Fail(409, "payment already exists"))
		return
	}

	commission := task.Budget * config.Global.Commission.Rate
	amountCents := int64((task.Budget) * 100)

	params := &stripe.PaymentIntentParams{
		Amount:   stripe.Int64(amountCents),
		Currency: stripe.String(strings.ToLower(task.Currency)),
		Metadata: map[string]string{
			"task_id":  strconv.Itoa(int(task.ID)),
			"payer_id": strconv.Itoa(int(uid)),
			"payee_id": strconv.Itoa(int(*task.AssigneeID)),
		},
		AutomaticPaymentMethods: &stripe.PaymentIntentAutomaticPaymentMethodsParams{
			Enabled: stripe.Bool(true),
		},
	}

	pi, err := paymentintent.New(params)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.Fail(500, "stripe error: "+err.Error()))
		return
	}

	// Auto-release after 48h
	autoRelease := time.Now().Add(48 * time.Hour)

	payment := models.Payment{
		TaskID:                task.ID,
		PayerID:               uid,
		PayeeID:               *task.AssigneeID,
		Amount:                task.Budget,
		Currency:              task.Currency,
		Commission:            commission,
		Status:                "pending",
		StripePaymentIntentID: pi.ID,
		AutoReleaseAt:         &autoRelease,
	}
	database.DB.Create(&payment)

	c.JSON(http.StatusOK, models.OK(gin.H{
		"client_secret":   pi.ClientSecret,
		"publishable_key": config.Global.Stripe.PublishableKey,
	}))
}

// POST /v1/payments/webhook  (Stripe webhook)
func (h *PaymentHandler) Webhook(c *gin.Context) {
	// In production: verify Stripe signature using config.Global.Stripe.WebhookSecret
	var event stripe.Event
	if err := c.ShouldBindJSON(&event); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, "invalid event"))
		return
	}

	switch event.Type {
	case "payment_intent.succeeded":
		var pi stripe.PaymentIntent
		if err := json.Unmarshal(event.Data.Raw, &pi); err == nil {
			database.DB.Model(&models.Payment{}).
				Where("stripe_payment_intent_id = ?", pi.ID).
				Update("status", "escrowed")
			// Record wallet transaction for payer
			var payment models.Payment
			database.DB.Where("stripe_payment_intent_id = ?", pi.ID).First(&payment)
			if payment.ID > 0 {
				database.DB.Create(&models.WalletTransaction{
					UserID:      payment.PayerID,
					Type:        "payment",
					Amount:      payment.Amount,
					Currency:    payment.Currency,
					Description: "Payment for task escrowed",
					RefID:       &payment.ID,
				})
			}
		}
	case "payment_intent.payment_failed":
		var pi stripe.PaymentIntent
		if err := json.Unmarshal(event.Data.Raw, &pi); err == nil {
			database.DB.Model(&models.Payment{}).
				Where("stripe_payment_intent_id = ?", pi.ID).
				Update("status", "failed")
		}
	}
	c.JSON(http.StatusOK, gin.H{"received": true})
}

// releasePayment is called when publisher confirms or auto-release triggers
func releasePayment(taskID uint) {
	var payment models.Payment
	if database.DB.Where("task_id = ? AND status = 'escrowed'", taskID).First(&payment).Error != nil {
		return
	}

	now := time.Now()
	database.DB.Model(&payment).Updates(map[string]interface{}{
		"status":      "released",
		"released_at": now,
	})

	netAmount := payment.Amount - payment.Commission
	database.DB.Create(&models.WalletTransaction{
		UserID:      payment.PayeeID,
		Type:        "release",
		Amount:      netAmount,
		Currency:    payment.Currency,
		Description: "Payment released for completed task",
		RefID:       &payment.ID,
	})
}
