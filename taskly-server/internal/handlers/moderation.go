package handlers

import (
	"regexp"
	"strings"
)

// Content moderation for user-generated text (App Store Guideline 1.2: apps with
// UGC must filter objectionable content). This is a lightweight server-side
// profanity/abuse filter applied to task titles/descriptions and chat messages.
// It is intentionally conservative — it blocks clearly objectionable terms rather
// than trying to catch everything — and complements the user-facing report/block
// flow and the 24h manual moderation of the Report queue.

// bannedTerms are matched case-insensitively on word boundaries. Keep this list
// focused on slurs / sexual / violent solicitation that have no place in a
// local-help marketplace.
var bannedTerms = []string{
	"fuck", "shit", "bitch", "cunt", "asshole", "bastard", "dick",
	"nigger", "nigga", "faggot", "retard", "whore", "slut",
	"rape", "kill yourself", "kys",
	"child porn", "cp ", "underage",
}

var bannedPattern = func() *regexp.Regexp {
	escaped := make([]string, len(bannedTerms))
	for i, t := range bannedTerms {
		escaped[i] = regexp.QuoteMeta(t)
	}
	// (?i) case-insensitive; surround with non-word-char boundaries so we don't
	// flag substrings inside innocent words (e.g. "Scunthorpe", "assassin").
	return regexp.MustCompile(`(?i)(^|\W)(` + strings.Join(escaped, "|") + `)(\W|$)`)
}()

// ContainsObjectionableContent reports whether text contains banned terms.
func ContainsObjectionableContent(text string) bool {
	return bannedPattern.MatchString(text)
}
