package models

import (
	"time"

	"github.com/lib/pq"
)

// ─── User ────────────────────────────────────────────────────────────────────

type User struct {
	BaseModel
	Nickname           string         `gorm:"size:100;not null" json:"nickname"`
	Email              string         `gorm:"size:255;uniqueIndex" json:"email,omitempty"`
	PasswordHash       string         `gorm:"size:255" json:"-"`
	Avatar             string         `gorm:"size:500" json:"avatar,omitempty"`
	Bio                string         `gorm:"size:500" json:"bio,omitempty"`
	SkillTags          pq.StringArray `gorm:"type:text[]" json:"skill_tags"`
	Rating             float64        `gorm:"default:0" json:"rating"`
	CompletedCount     int            `gorm:"default:0" json:"completed_count"`
	IsVerified         bool           `gorm:"default:false" json:"is_verified"`
	VerificationStatus string         `gorm:"size:20;default:'none'" json:"verification_status"` // none|pending|approved|rejected
	AppleUserID        string         `gorm:"size:255;uniqueIndex" json:"-"`
	DeviceToken        string         `gorm:"size:500" json:"-"`
}

// ─── Task ────────────────────────────────────────────────────────────────────

type Task struct {
	BaseModel
	Title          string         `gorm:"size:200;not null" json:"title"`
	Description    string         `gorm:"type:text" json:"description"`
	Category       string         `gorm:"size:50;not null" json:"category"`
	Budget         float64        `gorm:"type:decimal(10,2);not null" json:"budget"`
	Currency       string         `gorm:"size:3;default:'USD'" json:"currency"`
	Address        string         `gorm:"size:500" json:"address"`
	Latitude       *float64       `json:"latitude,omitempty"`
	Longitude      *float64       `json:"longitude,omitempty"`
	Deadline       *time.Time     `json:"deadline,omitempty"`
	Status         string         `gorm:"size:30;default:'open'" json:"status"`
	PublisherID    uint           `gorm:"not null;index" json:"publisher_id"`
	Publisher      *User          `gorm:"foreignKey:PublisherID" json:"publisher,omitempty"`
	AssigneeID     *uint          `gorm:"index" json:"assignee_id,omitempty"`
	Assignee       *User          `gorm:"foreignKey:AssigneeID" json:"assignee,omitempty"`
	Images         pq.StringArray `gorm:"type:text[]" json:"images"`
	ApplicantCount int            `gorm:"-" json:"applicant_count"`
}

// ─── ServiceCard ─────────────────────────────────────────────────────────────

type ServiceCard struct {
	BaseModel
	Title       string         `gorm:"size:200;not null" json:"title"`
	Description string         `gorm:"type:text" json:"description"`
	Category    string         `gorm:"size:50;not null" json:"category"`
	MinPrice    float64        `gorm:"type:decimal(10,2)" json:"min_price"`
	MaxPrice    float64        `gorm:"type:decimal(10,2)" json:"max_price"`
	Currency    string         `gorm:"size:3;default:'USD'" json:"currency"`
	ServiceArea string         `gorm:"size:200" json:"service_area"`
	SkillTags   pq.StringArray `gorm:"type:text[]" json:"skill_tags"`
	Images      pq.StringArray `gorm:"type:text[]" json:"images"`
	ProviderID  uint           `gorm:"not null;index" json:"provider_id"`
	Provider    *User          `gorm:"foreignKey:ProviderID" json:"provider,omitempty"`
	IsActive    bool           `gorm:"default:true" json:"is_active"`
}

// ─── Application ─────────────────────────────────────────────────────────────

type Application struct {
	BaseModel
	TaskID        uint    `gorm:"not null;index" json:"task_id"`
	ApplicantID   uint    `gorm:"not null;index" json:"applicant_id"`
	Applicant     *User   `gorm:"foreignKey:ApplicantID" json:"applicant,omitempty"`
	Message       string  `gorm:"type:text" json:"message"`
	ProposedPrice float64 `gorm:"type:decimal(10,2)" json:"proposed_price"`
	Status        string  `gorm:"size:20;default:'pending'" json:"status"` // pending|accepted|rejected
}

// ─── Payment ─────────────────────────────────────────────────────────────────

type Payment struct {
	BaseModel
	TaskID               uint       `gorm:"not null;index" json:"task_id"`
	PayerID              uint       `gorm:"not null;index" json:"payer_id"`
	PayeeID              uint       `gorm:"not null;index" json:"payee_id"`
	Amount               float64    `gorm:"type:decimal(10,2);not null" json:"amount"`
	Currency             string     `gorm:"size:3;default:'USD'" json:"currency"`
	Commission           float64    `gorm:"type:decimal(10,2);default:0" json:"commission"`
	Status               string     `gorm:"size:30;default:'pending'" json:"status"` // pending|escrowed|released|refunded|disputed
	StripePaymentIntentID string    `gorm:"size:255" json:"stripe_payment_intent_id,omitempty"`
	ReleasedAt           *time.Time `json:"released_at,omitempty"`
	AutoReleaseAt        *time.Time `gorm:"index" json:"auto_release_at,omitempty"`
}

// ─── Message ─────────────────────────────────────────────────────────────────

type Message struct {
	BaseModel
	SenderID   uint   `gorm:"not null;index" json:"sender_id"`
	ReceiverID uint   `gorm:"not null;index" json:"receiver_id"`
	TaskID     *uint  `gorm:"index" json:"task_id,omitempty"`
	Content    string `gorm:"type:text;not null" json:"content"`
	ImageURL   string `gorm:"size:500" json:"image_url,omitempty"`
	IsRead     bool   `gorm:"default:false" json:"is_read"`
}

// ─── Review ──────────────────────────────────────────────────────────────────

type Review struct {
	BaseModel
	TaskID     uint           `gorm:"not null;index" json:"task_id"`
	ReviewerID uint           `gorm:"not null;index" json:"reviewer_id"`
	Reviewer   *User          `gorm:"foreignKey:ReviewerID" json:"reviewer,omitempty"`
	RevieweeID uint           `gorm:"not null;index" json:"reviewee_id"`
	Rating     int            `gorm:"not null" json:"rating"`
	Comment    string         `gorm:"type:text" json:"comment"`
	Images     pq.StringArray `gorm:"type:text[]" json:"images"`
}

// ─── Verification ─────────────────────────────────────────────────────────────

type Verification struct {
	BaseModel
	UserID          uint       `gorm:"not null;uniqueIndex" json:"user_id"`
	RealName        string     `gorm:"size:100" json:"real_name"`
	DocumentType    string     `gorm:"size:50" json:"document_type"`
	FrontImageURL   string     `gorm:"size:500" json:"front_image_url"`
	BackImageURL    string     `gorm:"size:500" json:"back_image_url,omitempty"`
	Status          string     `gorm:"size:20;default:'pending'" json:"status"`
	RejectionReason string     `gorm:"size:500" json:"rejection_reason,omitempty"`
	ReviewedAt      *time.Time `json:"reviewed_at,omitempty"`
}

// ─── Report ──────────────────────────────────────────────────────────────────

type Report struct {
	BaseModel
	ReporterID uint   `gorm:"not null;index" json:"reporter_id"`
	TargetType string `gorm:"size:20;not null" json:"target_type"` // task|user|message
	TargetID   uint   `gorm:"not null;index" json:"target_id"`
	Reason     string `gorm:"size:500" json:"reason"`
	Status     string `gorm:"size:20;default:'pending'" json:"status"` // pending|reviewed|dismissed
}

// ─── WalletTransaction ────────────────────────────────────────────────────────

type WalletTransaction struct {
	BaseModel
	UserID      uint    `gorm:"not null;index" json:"user_id"`
	Type        string  `gorm:"size:30;not null" json:"type"` // payment|release|refund|withdrawal
	Amount      float64 `gorm:"type:decimal(10,2);not null" json:"amount"`
	Currency    string  `gorm:"size:3;default:'USD'" json:"currency"`
	Description string  `gorm:"size:500" json:"description"`
	RefID       *uint   `gorm:"index" json:"ref_id,omitempty"`
}
