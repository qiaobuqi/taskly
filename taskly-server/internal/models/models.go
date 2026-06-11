package models

import (
	"time"

)

// ─── User ────────────────────────────────────────────────────────────────────

type User struct {
	BaseModel
	Nickname           string         `gorm:"size:100;not null" json:"nickname"`
	// MySQL has no partial unique indexes, and a plain unique index would treat
	// every empty string ("") as a collision — so the 2nd email-only user (blank
	// apple_user_id) or apple-only user (blank email) would fail to insert.
	// Uniqueness is therefore enforced at the application layer (Register checks the
	// email already exists; AppleLogin looks up by apple_user_id); these are plain
	// non-unique indexes purely for lookup speed.
	Email              string         `gorm:"size:255;index" json:"email,omitempty"`
	PasswordHash       string         `gorm:"size:255" json:"-"`
	Avatar             string         `gorm:"size:500" json:"avatar,omitempty"`
	Bio                string         `gorm:"size:500" json:"bio,omitempty"`
	SkillTags          StringArray `gorm:"type:json" json:"skill_tags"`
	Rating             float64        `gorm:"default:0" json:"rating"`
	CompletedCount     int            `gorm:"default:0" json:"completed_count"`
	IsVerified         bool           `gorm:"default:false" json:"is_verified"`
	VerificationStatus string         `gorm:"size:20;default:'none'" json:"verification_status"` // none|pending|approved|rejected
	AppleUserID        string         `gorm:"size:255;index" json:"-"` // uniqueness enforced in AppleLogin handler
	DeviceToken        string         `gorm:"size:500" json:"-"`
	IsAdmin            bool           `gorm:"default:false" json:"-"` // gates /v1/admin/*; flipped manually in the DB
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
	Images         StringArray `gorm:"type:json" json:"images"`
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
	SkillTags   StringArray `gorm:"type:json" json:"skill_tags"`
	Images      StringArray `gorm:"type:json" json:"images"`
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
	Images     StringArray `gorm:"type:json" json:"images"`
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

// ─── Block ───────────────────────────────────────────────────────────────────
//
// One row per (blocker → blocked) pair. Blocking is one-directional in intent but
// the feed/message filters hide content in BOTH directions, so a blocked user also
// stops seeing the blocker (App Store Guideline 1.2: content must be removed from
// the user's feed instantly). Creating a block also files a Report so the developer
// is notified of the objectionable content/behaviour.
type Block struct {
	BaseModel
	BlockerID uint `gorm:"not null;index:idx_blocker_blocked,unique" json:"blocker_id"`
	BlockedID uint `gorm:"not null;index:idx_blocker_blocked,unique" json:"blocked_id"`
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

// ─── EmailCode ───────────────────────────────────────────────────────────────
//
// One row per email; the latest verification code for registration. We upsert on
// email so an address only ever has its newest code. Attempts caps brute-forcing.
type EmailCode struct {
	ID        uint      `gorm:"primarykey" json:"id"`
	Email     string    `gorm:"size:255;uniqueIndex" json:"email"`
	Code      string    `gorm:"size:6" json:"-"`
	ExpiresAt time.Time `json:"expires_at"`
	Attempts  int       `gorm:"default:0" json:"-"`
	CreatedAt time.Time `json:"created_at"` // also used for the 60s resend cooldown
	UpdatedAt time.Time `json:"-"`
}

// ─── Analytics ───────────────────────────────────────────────────────────────
//
// One row per client event. Kept deliberately flat and append-only (no soft
// delete) so DAU / retention can be computed with simple group-bys. Identity for
// those metrics is COALESCE(user_id, anon_id): anon_id (a per-install UUID) keeps
// pre-login app_opens countable, and ties them to the user once they sign in.
type AnalyticsEvent struct {
	ID         uint      `gorm:"primarykey" json:"id"`
	CreatedAt  time.Time `gorm:"index" json:"created_at"`          // server receive time
	UserID     *uint     `gorm:"index" json:"user_id,omitempty"`   // null when logged out
	AnonID     string    `gorm:"size:64;index" json:"anon_id"`     // per-install id
	SessionID  string    `gorm:"size:64;index" json:"session_id"`
	Event      string    `gorm:"size:64;index" json:"event"`       // e.g. app_open, login, post_task
	Props      string    `gorm:"type:json" json:"props"`           // arbitrary JSON
	Platform   string    `gorm:"size:16" json:"platform"`
	AppVersion string    `gorm:"size:16" json:"app_version"`
	ClientTS   time.Time `json:"client_ts"`
	EventDate  string    `gorm:"size:10;index" json:"event_date"`  // YYYY-MM-DD for DAU/retention
}
