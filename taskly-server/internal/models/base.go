package models

import (
	"time"

	"gorm.io/gorm"
)

type BaseModel struct {
	ID        uint           `gorm:"primarykey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

type Response struct {
	Code    int         `json:"code"`
	Message string      `json:"message"`
	Data    interface{} `json:"data"`
}

type PageData struct {
	List     interface{} `json:"list"`
	Total    int64       `json:"total"`
	Page     int         `json:"page"`
	PageSize int         `json:"page_size"`
}

func OK(data interface{}) Response {
	return Response{Code: 200, Message: "success", Data: data}
}

func Fail(code int, msg string) Response {
	return Response{Code: code, Message: msg, Data: nil}
}

func Page(list interface{}, total int64, page, size int) Response {
	return Response{Code: 200, Message: "success", Data: PageData{
		List: list, Total: total, Page: page, PageSize: size,
	}}
}
