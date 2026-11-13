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
