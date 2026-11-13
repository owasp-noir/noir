package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type AuthService interface {
	GetUserCacheInfo(ctx *gin.Context, token string) (any, error)
}

type AuthUserMiddleware struct {
	authService AuthService
	siteService SiteService
}

type SiteSecurity struct {
	LoginRequired bool
}

type SiteService interface {
	GetSiteSecurity(ctx *gin.Context) (*SiteSecurity, error)
}

// Auth sets the user when one is logged in, and lets everyone through.
func (am *AuthUserMiddleware) Auth() gin.HandlerFunc {
	return func(ctx *gin.Context) {
		token := ctx.GetHeader("Authorization")
		if len(token) == 0 {
			ctx.Next()
			return
		}
		userInfo, err := am.authService.GetUserCacheInfo(ctx, token)
		if err != nil {
			ctx.Next()
			return
		}
		ctx.Set("user", userInfo)
		ctx.Next()
	}
}

// EjectUserBySiteInfo refuses a caller without a user only when the site
// requires a login.
func (am *AuthUserMiddleware) EjectUserBySiteInfo() gin.HandlerFunc {
	return func(ctx *gin.Context) {
		siteInfo, _ := am.siteService.GetSiteSecurity(ctx)
		if siteInfo == nil || !siteInfo.LoginRequired {
			ctx.Next()
			return
		}
		if _, ok := ctx.Get("user"); !ok {
			handler.HandleResponse(ctx, errors.Unauthorized(reason.UnauthorizedError), nil)
			ctx.Abort()
			return
		}
		ctx.Next()
	}
}

// MustAuth refuses a caller without a token.
func (am *AuthUserMiddleware) MustAuth() gin.HandlerFunc {
	return func(ctx *gin.Context) {
		if ctx.GetHeader("Authorization") == "" {
			ctx.AbortWithStatus(http.StatusUnauthorized)
			return
		}
		ctx.Next()
	}
}

// AdminAuth refuses a caller without a token.
func (am *AuthUserMiddleware) AdminAuth() gin.HandlerFunc {
	return func(ctx *gin.Context) {
		if ctx.GetHeader("Authorization") == "" {
			ctx.AbortWithStatus(http.StatusUnauthorized)
			return
		}
		ctx.Next()
	}
}
