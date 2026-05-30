package database

import (
	"fmt"
	"log"

	"taskly-server/internal/config"
	"taskly-server/internal/models"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

var DB *gorm.DB

func Init() error {
	cfg := config.Global.Database
	dsn := fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=%s sslmode=%s TimeZone=UTC",
		cfg.Host, cfg.Port, cfg.User, cfg.Password, cfg.Name, cfg.SSLMode,
	)

	logLevel := logger.Info
	if config.Global.Server.Mode == "release" {
		logLevel = logger.Error
	}

	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{
		Logger: logger.Default.LogMode(logLevel),
	})
	if err != nil {
		return fmt.Errorf("open db: %w", err)
	}

	if err := autoMigrate(db); err != nil {
		return fmt.Errorf("migrate: %w", err)
	}

	DB = db
	log.Println("✅ Database connected")
	return nil
}

func autoMigrate(db *gorm.DB) error {
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
		&models.WalletTransaction{},
	)
}
