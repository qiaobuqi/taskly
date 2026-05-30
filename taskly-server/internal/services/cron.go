package services

import (
	"log"
	"time"

	"taskly-server/internal/database"
	"taskly-server/internal/models"

	"github.com/robfig/cron/v3"
)

func StartCron() {
	c := cron.New()

	// Every hour: auto-release payments that hit 48h
	c.AddFunc("0 * * * *", autoReleasePayments)

	c.Start()
	log.Println("✅ Cron started")
}

func autoReleasePayments() {
	var payments []models.Payment
	database.DB.Where(
		"status = 'escrowed' AND auto_release_at <= ?",
		time.Now(),
	).Find(&payments)

	for _, p := range payments {
		now := time.Now()
		database.DB.Model(&p).Updates(map[string]interface{}{
			"status":      "released",
			"released_at": now,
		})

		netAmount := p.Amount - p.Commission
		database.DB.Create(&models.WalletTransaction{
			UserID:      p.PayeeID,
			Type:        "release",
			Amount:      netAmount,
			Currency:    p.Currency,
			Description: "Auto-released payment (48h timeout)",
			RefID:       &p.ID,
		})

		// Update task to completed
		database.DB.Model(&models.Task{}).Where("id = ?", p.TaskID).
			Update("status", "completed")

		log.Printf("Auto-released payment %d for task %d", p.ID, p.TaskID)
	}
}
