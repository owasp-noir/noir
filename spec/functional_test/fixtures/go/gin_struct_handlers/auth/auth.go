package auth

import "github.com/gin-gonic/gin"

type Auth struct{}

// RequireUser refuses a caller without a user.
func (a *Auth) RequireUser(c *gin.Context) {
	a.evaluateOr401(c)
}

// OptionalUser checks credentials when present and lets anonymous callers in.
func (a *Auth) OptionalUser(c *gin.Context) {
	if !a.evaluate(c) {
		c.Next()
	}
}

func (a *Auth) evaluate(c *gin.Context) bool {
	if c.GetString("user") == "banned" {
		c.AbortWithStatus(403)
		return true
	}
	return false
}

func (a *Auth) evaluateOr401(c *gin.Context) {
	if !a.evaluate(c) {
		a.abort401(c)
	}
}

func (a *Auth) abort401(c *gin.Context) {
	c.AbortWithStatus(401)
}
