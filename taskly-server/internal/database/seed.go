package database

import (
	"log"
	"time"

	"taskly-server/internal/models"

	"golang.org/x/crypto/bcrypt"
)

// SeedReviewData guarantees the App Review demo account always has a populated
// Messages tab. App Review repeatedly hit an "empty Messages screen" (Guideline
// 2.1) because conversations are derived from the `messages` table and the demo
// data was only ever inserted by hand — so any DB reset left the tab empty.
//
// This runs on every startup and is fully idempotent: it ensures the demo
// account + a few counterpart users exist, and back-fills a realistic set of
// message threads only when they are missing. It never duplicates or overwrites
// real user data.
func SeedReviewData() {
	demo := ensureUser("appreview@taskly.app", "App Review", "Review2026!", "", nil, 0, false)
	if demo == nil {
		return
	}

	// Counterpart "taskers" the demo account chats with. Verified + rated so the
	// profiles look like a real marketplace.
	mike := ensureUser("mike.t@taskly.app", "Mike T.", "Taskly2026!",
		"Network & smart-home setup. Wi-Fi mesh, TV mounting, IT help.",
		[]string{"IT", "Networking"}, 4.7, true)
	david := ensureUser("david.l@taskly.app", "David L.", "Taskly2026!",
		"Removalist & handyman, 5 yrs exp.",
		[]string{"Moving", "Furniture"}, 4.8, true)
	emma := ensureUser("emma.w@taskly.app", "Emma W.", "Taskly2026!",
		"Detail-oriented home cleaner.",
		[]string{"Cleaning", "Errands"}, 4.9, true)
	sophie := ensureUser("sophie.k@taskly.app", "Sophie K.", "Taskly2026!",
		"Gardening, lawn care & green-waste removal.",
		[]string{"Gardening", "Outdoor"}, 4.6, true)

	base := time.Now().Add(-72 * time.Hour)

	ensureThread(demo.ID, mike.ID, base, []seedMsg{
		{mike.ID, "Hi! I saw your Wi-Fi mesh task — happy to help. How big is the place?"},
		{demo.ID, "Hey Mike, it's a 3-storey townhouse. Wi-Fi drops out upstairs."},
		{mike.ID, "Three floors usually needs 3 mesh nodes. I can supply or use yours."},
		{demo.ID, "Let's use mine — I already bought a 3-pack."},
		{mike.ID, "Perfect. Saturday afternoon works for me. I'll also tidy the cabling."},
		{demo.ID, "Saturday 2pm is great. See you then 👍"},
		{mike.ID, "Confirmed for Sat 2pm. I'll bring a ladder and label everything."},
	})

	ensureThread(demo.ID, david.ID, base.Add(6*time.Hour), []seedMsg{
		{demo.ID, "Hi David, quoting on a 2-bedroom move — do you have a van?"},
		{david.ID, "I have a 3-ton van and one offsider. Easy half-day job."},
		{david.ID, "Any heavy items like a piano or a large fridge?"},
		{demo.ID, "Just a fridge and a sofa bed. Ground floor both ends."},
		{david.ID, "No worries. $90/hr, ~3 hours. I can do this Sunday morning."},
		{demo.ID, "Sounds fair. Let's lock in Sunday 9am."},
	})

	ensureThread(demo.ID, emma.ID, base.Add(12*time.Hour), []seedMsg{
		{emma.ID, "Hi! I saw you're after a regular house clean — is it weekly?"},
		{demo.ID, "Hi Emma, fortnightly would be ideal. 2 bed / 1 bath."},
		{emma.ID, "I can do fortnightly Fridays. Includes kitchen, bath, floors, dusting."},
		{demo.ID, "Great. Do you bring your own products?"},
		{emma.ID, "Yes, eco-friendly supplies included. First clean this Friday?"},
		{demo.ID, "Friday works. Thanks Emma!"},
	})

	ensureThread(demo.ID, sophie.ID, base.Add(30*time.Hour), []seedMsg{
		{demo.ID, "Hi Sophie, the back lawn is overgrown — can you mow and edge it?"},
		{sophie.ID, "Absolutely. Roughly how big is the lawn?"},
		{demo.ID, "About 60 sqm, plus a small hedge to trim."},
		{sophie.ID, "I can mow, edge, trim the hedge and take the green waste. $70 total."},
		{demo.ID, "Perfect, when are you free?"},
		{sophie.ID, "Thursday afternoon. I'll text when I'm 20 mins out."},
	})

	log.Printf("✅ Review demo data seeded (account appreview@taskly.app)")
}

type seedMsg struct {
	senderID uint
	content  string
}

// ensureUser finds a user by email or creates one. Existing users are returned
// untouched (we never overwrite a real profile or password).
func ensureUser(email, nickname, password, bio string, tags []string, rating float64, verified bool) *models.User {
	var u models.User
	if err := DB.Where("email = ?", email).First(&u).Error; err == nil {
		return &u
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		log.Printf("seed: hash failed for %s: %v", email, err)
		return nil
	}
	status := "none"
	if verified {
		status = "approved"
	}
	u = models.User{
		Nickname:           nickname,
		Email:              email,
		PasswordHash:       string(hash),
		Bio:                bio,
		SkillTags:          models.StringArray(tags),
		Rating:             rating,
		IsVerified:         verified,
		VerificationStatus: status,
	}
	if err := DB.Create(&u).Error; err != nil {
		log.Printf("seed: create user %s failed: %v", email, err)
		return nil
	}
	return &u
}

// ensureThread inserts a message thread between two users only if none exists,
// stamping each message a minute apart starting at `start` so the ordering and
// "last message" preview look natural.
func ensureThread(a, b uint, start time.Time, msgs []seedMsg) {
	var count int64
	DB.Model(&models.Message{}).
		Where("(sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)", a, b, b, a).
		Count(&count)
	if count > 0 {
		return
	}
	for i, m := range msgs {
		receiver := a
		if m.senderID == a {
			receiver = b
		}
		ts := start.Add(time.Duration(i) * time.Minute)
		msg := models.Message{
			SenderID:   m.senderID,
			ReceiverID: receiver,
			Content:    m.content,
			IsRead:     true,
		}
		msg.CreatedAt = ts
		msg.UpdatedAt = ts
		DB.Create(&msg)
	}
}
