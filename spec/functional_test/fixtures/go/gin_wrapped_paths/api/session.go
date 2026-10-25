package api

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type Session struct {
	Status int
}

// Auth returns the caller's session; an anonymous caller's carries 401.
func Auth(c *gin.Context) (s *Session) {
	if c.GetHeader("Authorization") == "" {
		return &Session{Status: http.StatusUnauthorized}
	}
	return &Session{}
}

// Abort refuses the request when the session is not valid.
func (m *Session) Abort(c *gin.Context) bool {
	if m.Status == 0 {
		return false
	}

	c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})

	return true
}

// logged only records the request.
func logged(c *gin.Context) bool {
	c.Set("seen", true)
	return false
}
