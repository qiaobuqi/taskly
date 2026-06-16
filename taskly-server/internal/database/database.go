package database

import (
	"fmt"
	"log"

	"taskly-server/internal/config"
	"taskly-server/internal/models"

	"gorm.io/driver/mysql"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

var DB *gorm.DB

func Init() error {
	cfg := config.Global.Database
	charset := cfg.Charset
	if charset == "" {
		charset = "utf8mb4"
	}
	// MySQL DSN: user:pass@tcp(host:port)/dbname?charset=...&parseTime=True&loc=Local
	dsn := fmt.Sprintf(
		"%s:%s@tcp(%s:%d)/%s?charset=%s&parseTime=True&loc=Local",
		cfg.User, cfg.Password, cfg.Host, cfg.Port, cfg.Name, charset,
	)

	logLevel := logger.Info
	if config.Global.Server.Mode == "release" {
		logLevel = logger.Error
	}

	db, err := gorm.Open(mysql.Open(dsn), &gorm.Config{
		Logger: logger.Default.LogMode(logLevel),
	})
	if err != nil {
		return fmt.Errorf("open db: %w", err)
	}

	if err := autoMigrate(db); err != nil {
		return fmt.Errorf("migrate: %w", err)
	}

	DB = db
	log.Printf("✅ Database connected (mysql %s/%s)", cfg.Host, cfg.Name)

	// Guarantee the App Review demo account always has a populated Messages tab
	// (idempotent — see seed.go). Fixes the recurring "empty Messages screen"
	// rejection (Guideline 2.1).
	SeedReviewData()
	return nil
}

func autoMigrate(db *gorm.DB) error {
	// GORM creates/updates tables to match the models. Uniqueness for users.email
	// and users.apple_user_id is enforced in the handlers (not via DB unique index)
	// because MySQL has no partial indexes and a plain unique index would collide on
	// the empty-string default shared by email-only / apple-only accounts.
	return db.AutoMigrate(
		&models.User{},
		&models.Task{},
		&models.ServiceCard{},
		&models.Application{},
		&models.Payment{},
		&models.Message{},
		&models.Review{},
		&models.Verification{},
		&models.Report{},
		&models.Block{},
		&models.WalletTransaction{},
		&models.AnalyticsEvent{},
		&models.EmailCode{},
	)
}
