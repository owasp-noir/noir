package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type User struct{ Hash string }
type siteInfo struct{}
type AuthUserMiddleware struct{ site siteInfo }

func parseToken(r *http.Request) (*User, bool, error) { return nil, false, nil }
func checkCsrf(r *http.Request, u *User) error         { return nil }
func (siteInfo) MCPEnabled(c *gin.Context) (bool, error) { return true, nil }

// Anonymous callers skip the only refusal and reach Next.
func SetUser() gin.HandlerFunc {
	return func(c *gin.Context) {
		user, session, err := parseToken(c.Request)
		if err == nil {
			c.Set("user", user)
			if session {
				err = checkCsrf(c.Request, user)
				if err != nil {
					c.AbortWithStatus(http.StatusUnauthorized)
					return
				}
			}
		}
		c.Next()
	}
}

// The feature setting treats every caller alike.
func (am *AuthUserMiddleware) AuthMcpEnable() gin.HandlerFunc {
	return func(ctx *gin.Context) {
		enabled, err := am.site.MCPEnabled(ctx)
		if err != nil {
			ctx.AbortWithStatus(http.StatusInternalServerError)
			return
		}
		if enabled {
			ctx.Next()
			return
		}
		ctx.AbortWithStatus(http.StatusForbidden)
	}
}

func requireUser(c *gin.Context) {
	user, _ := c.Get("user")
	if user == nil {
		c.AbortWithStatus(http.StatusUnauthorized)
		return
	}
	c.Next()
}

func requireToken(c *gin.Context) {
	token := c.GetHeader("Authorization")
	if token == "" {
		c.AbortWithStatus(http.StatusUnauthorized)
		return
	}
	c.Next()
}

func requireAdmin(c *gin.Context) {
	user, _ := c.Get("user")
	if !isAdmin(user) {
		c.AbortWithStatus(http.StatusForbidden)
		return
	}
	c.Next()
}

func isAdmin(user any) bool { return user != nil }
func handler(c *gin.Context) {}

func main() {
	r := gin.New()
	am := &AuthUserMiddleware{}
	r.GET("/optional", SetUser(), handler)
	r.POST("/mcp/message", am.AuthMcpEnable(), handler)
	r.GET("/user", requireUser, handler)
	r.GET("/token", requireToken, handler)
	r.GET("/admin", requireAdmin, handler)
	group := r.Group("/group")
	group.Use(SetUser(), am.AuthMcpEnable())
	group.GET("/public", handler)
	group.GET("/private", requireToken, handler)
}
