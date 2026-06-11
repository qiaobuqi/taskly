package config

import (
	"github.com/spf13/viper"
)

type Config struct {
	Server   ServerConfig
	Database DatabaseConfig
	JWT      JWTConfig
	Stripe   StripeConfig
	Apple    AppleConfig
	Commission CommissionConfig
	DirectMail DirectMailConfig
}

type DirectMailConfig struct {
	AccessKeyID     string `mapstructure:"access_key_id"`
	AccessKeySecret string `mapstructure:"access_key_secret"`
	AccountName     string `mapstructure:"account_name"` // verified DirectMail sender, e.g. no-reply@cnirv.com
	FromAlias       string `mapstructure:"from_alias"`
	Region          string
}

type ServerConfig struct {
	Port string
	Mode string
}

type DatabaseConfig struct {
	Host     string
	Port     int
	User     string
	Password string
	Name     string
	Charset  string
	SSLMode  string `mapstructure:"sslmode"`
}

type JWTConfig struct {
	Secret      string
	ExpireHours int `mapstructure:"expire_hours"`
}

type StripeConfig struct {
	SecretKey      string `mapstructure:"secret_key"`
	PublishableKey string `mapstructure:"publishable_key"`
	WebhookSecret  string `mapstructure:"webhook_secret"`
}

type AppleConfig struct {
	TeamID   string `mapstructure:"team_id"`
	BundleID string `mapstructure:"bundle_id"`
}

type CommissionConfig struct {
	Rate float64
}

var Global Config

func InitConfig(file string) error {
	viper.SetConfigFile(file)
	viper.AutomaticEnv()
	if err := viper.ReadInConfig(); err != nil {
		return err
	}
	return viper.Unmarshal(&Global)
}
