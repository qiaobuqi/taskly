package middleware

import (
	"bytes"
	"io"
	"log"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// bodyLogWriter captures the response body as it is written so we can log it.
type bodyLogWriter struct {
	gin.ResponseWriter
	body *bytes.Buffer
}

func (w bodyLogWriter) Write(b []byte) (int, error) {
	w.body.Write(b)
	return w.ResponseWriter.Write(b)
}

const maxLoggedBody = 2 << 10 // 2 KB; keeps logs readable during 联调

func truncate(b []byte) string {
	if len(b) > maxLoggedBody {
		return string(b[:maxLoggedBody]) + "…(truncated)"
	}
	return string(b)
}

// RequestLogger logs each API call's method, path, request body, status, latency,
// and response body. Intended for front-back integration debugging (前后端联调).
// It skips binary endpoints (upload, websocket) to avoid dumping noise.
func RequestLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		path := c.Request.URL.Path
		// Don't slurp bodies for binary/streaming endpoints, and crucially NOT for the
		// Stripe webhook — its signature is computed over the exact raw bytes, so the
		// body must reach the handler completely untouched.
		skipBody := path == "/v1/upload/image" || path == "/v1/messages/ws" || path == "/v1/payments/webhook"
		// Never log auth payloads: request bodies carry plaintext passwords /
		// Apple identity tokens, and responses carry the session JWT.
		sensitive := strings.HasPrefix(path, "/v1/auth/")

		var reqBody []byte
		if !skipBody && c.Request.Body != nil {
			reqBody, _ = io.ReadAll(c.Request.Body)
			c.Request.Body = io.NopCloser(bytes.NewBuffer(reqBody))
		}

		blw := &bodyLogWriter{ResponseWriter: c.Writer, body: &bytes.Buffer{}}
		c.Writer = blw

		start := time.Now()
		c.Next()
		latency := time.Since(start)

		reqLog, respLog := truncate(reqBody), truncate(blw.body.Bytes())
		if sensitive {
			reqLog, respLog = "[redacted]", "[redacted]"
		}
		log.Printf("➡️  %s %s\n    req:  %s", c.Request.Method, path, reqLog)
		log.Printf("⬅️  %d %s (%v)\n    resp: %s",
			c.Writer.Status(), path, latency.Round(time.Millisecond), respLog)
	}
}
