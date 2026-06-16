package main

import (
	"log"
	"os"

	"taskly-server/internal/config"
	"taskly-server/internal/database"
	"taskly-server/internal/mail"
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

	// APNs 推送服务(未配置则静默跳过,不影响主流程)
	if err := services.InitPush(); err != nil {
		log.Printf("push init error (continuing without push): %v", err)
	}

	// 邮件子系统:收信(:25)与提交(:587/:465)服务,各自 goroutine 运行,
	// 出错只记日志,不影响 Taskly 主 API。由 MAIL_ENABLED=1 开启。
	mail.InitConfig()
	if mail.Cfg.Enabled {
		go mail.StartReceiver()
		go mail.StartSubmission()
	}

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
