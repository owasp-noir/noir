package auth

import (
	"example.com/app/session"
	"github.com/gin-gonic/gin"
)

type Verifier interface{ Verify(c *gin.Context) }

type Auth struct{ V Verifier }

// RequireLogin hands the request to another package's check.
func (a *Auth) RequireLogin(c *gin.Context) {
	session.Require(c)
}

// RequireToken hands the request to an interface field.
func (a *Auth) RequireToken(c *gin.Context) {
	a.V.Verify(c)
}
