package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"taskly-server/internal/database"
	"taskly-server/internal/middleware"
	"taskly-server/internal/models"

	"github.com/gin-gonic/gin"
)

type AnalyticsHandler struct{}

func NewAnalyticsHandler() *AnalyticsHandler { return &AnalyticsHandler{} }

// POST /v1/analytics/events  (optional auth)
// Accepts a batch of client events. Logged-out callers still count toward DAU via
// their per-install anon_id; once they log in the JWT attaches user_id.
func (h *AnalyticsHandler) Ingest(c *gin.Context) {
	var req struct {
		AnonID     string `json:"anon_id"`
		Platform   string `json:"platform"`
		AppVersion string `json:"app_version"`
		Events     []struct {
			Event     string                 `json:"event"`
			SessionID string                 `json:"session_id"`
			TS        int64                  `json:"ts"` // client epoch milliseconds
			Props     map[string]interface{} `json:"props"`
		} `json:"events"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.Fail(400, err.Error()))
		return
	}
	if len(req.Events) == 0 {
		c.JSON(http.StatusOK, models.OK(gin.H{"accepted": 0}))
		return
	}

	var userID *uint
	if uid := middleware.CurrentUserID(c); uid != 0 {
		userID = &uid
	}

	now := time.Now()
	rows := make([]models.AnalyticsEvent, 0, len(req.Events))
	for _, e := range req.Events {
		if e.Event == "" {
			continue
		}
		propsJSON := "{}"
		if e.Props != nil {
			if b, err := json.Marshal(e.Props); err == nil {
				propsJSON = string(b)
			}
		}
		clientTS := now
		if e.TS > 0 {
			clientTS = time.UnixMilli(e.TS)
		}
		rows = append(rows, models.AnalyticsEvent{
			CreatedAt:  now,
			UserID:     userID,
			AnonID:     req.AnonID,
			SessionID:  e.SessionID,
			Event:      e.Event,
			Props:      propsJSON,
			Platform:   req.Platform,
			AppVersion: req.AppVersion,
			ClientTS:   clientTS,
			EventDate:  now.Format("2006-01-02"),
		})
	}
	if len(rows) > 0 {
		if err := database.DB.Create(&rows).Error; err != nil {
			c.JSON(http.StatusInternalServerError, models.Fail(500, "ingest failed"))
			return
		}
	}
	c.JSON(http.StatusOK, models.OK(gin.H{"accepted": len(rows)}))
}

// GET /v1/admin/analytics/dau?days=14
// Daily active "actors" (distinct user_id or anon_id) per day.
func (h *AnalyticsHandler) DAU(c *gin.Context) {
	days := 14
	if d := c.Query("days"); d != "" {
		if n, err := time.ParseDuration(d + "h"); err == nil && n > 0 {
			days = int(n.Hours())
		}
	}
	since := time.Now().AddDate(0, 0, -days).Format("2006-01-02")

	type Row struct {
		Date string `json:"date"`
		DAU  int64  `json:"dau"`
	}
	var out []Row
	database.DB.Raw(`
		SELECT event_date AS date,
		       COUNT(DISTINCT COALESCE(CAST(user_id AS CHAR), anon_id)) AS dau
		FROM analytics_events
		WHERE event_date >= ?
		GROUP BY event_date
		ORDER BY event_date`, since).Scan(&out)
	c.JSON(http.StatusOK, models.OK(out))
}

// GET /v1/admin/analytics/retention
// Cohort retention: for each first-seen day, what share of new actors return on
// day 1 and day 7. Identity = COALESCE(user_id, anon_id).
func (h *AnalyticsHandler) Retention(c *gin.Context) {
	type Row struct {
		Cohort     string `json:"cohort"`
		CohortSize int64  `json:"cohort_size"`
		D1         int64  `json:"d1"`
		D7         int64  `json:"d7"`
	}
	var out []Row
	// event_date is stored as a 'YYYY-MM-DD' string, which sorts chronologically, so
	// MIN() gives the cohort day. Day-N retention compares against the string form of
	// cohort + N days.
	database.DB.Raw(`
		WITH actors AS (
			-- Force one collation: CAST(user_id) and the anon_id column otherwise carry
			-- different collations, so COALESCE'd actor comparisons throw "illegal mix".
			SELECT (COALESCE(CAST(user_id AS CHAR), anon_id) COLLATE utf8mb4_general_ci) AS actor,
			       event_date AS d
			FROM analytics_events
		),
		first_seen AS (
			SELECT actor, MIN(d) AS cohort FROM actors GROUP BY actor
		),
		activity AS (
			SELECT DISTINCT actor, d FROM actors
		)
		SELECT f.cohort AS cohort,
		       COUNT(DISTINCT f.actor) AS cohort_size,
		       COUNT(DISTINCT CASE WHEN STR_TO_DATE(a.d,'%Y-%m-%d') = DATE_ADD(STR_TO_DATE(f.cohort,'%Y-%m-%d'), INTERVAL 1 DAY) THEN a.actor END) AS d1,
		       COUNT(DISTINCT CASE WHEN STR_TO_DATE(a.d,'%Y-%m-%d') = DATE_ADD(STR_TO_DATE(f.cohort,'%Y-%m-%d'), INTERVAL 7 DAY) THEN a.actor END) AS d7
		FROM first_seen f
		JOIN activity a ON a.actor = f.actor
		GROUP BY f.cohort
		ORDER BY f.cohort`).Scan(&out)
	c.JSON(http.StatusOK, models.OK(out))
}
