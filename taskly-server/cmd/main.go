package main

import (
	"log"
	"os"

	"taskly-server/internal/config"
	"taskly-server/internal/database"
	"taskly-server/internal/middleware"
	"taskly-server/internal/routes"
	"taskly-server/internal/services"

	"github.com/gin-gonic/gin"
)

func main() {
	configFile := os.Getenv("CONFIG_FILE")
	if configFile == "" {
		configFile = "configs/config.yaml"
	}

	if err := config.InitConfig(configFile); err != nil {
		log.Fatalf("config error: %v", err)
	}

	if err := database.Init(); err != nil {
		log.Fatalf("database error: %v", err)
	}

	services.StartCron()

	gin.SetMode(config.Global.Server.Mode)
	r := gin.New()
	r.Use(gin.Logger())
	r.Use(gin.Recovery())
	r.Use(middleware.CORS())
	r.Use(middleware.RequestLogger())

	routes.Setup(r)

	port := config.Global.Server.Port
	if port == "" {
		port = "8080"
	}
	log.Printf("🚀 Taskly server running on :%s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
