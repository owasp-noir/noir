package router

import (
	"github.com/gin-gonic/gin"

	"example.com/registrar/middleware"
)

type APIRouter struct{}

func (a *APIRouter) RegisterMustUnAuthAPIRouter(authUserMiddleware *middleware.AuthUserMiddleware, r *gin.RouterGroup) {
	r.GET("/siteinfo", func(ctx *gin.Context) {})
	r.POST("/user/login/email", func(ctx *gin.Context) {})
}

func (a *APIRouter) RegisterUnAuthAPIRouter(r *gin.RouterGroup) {
	r.GET("/personal/question/page", func(ctx *gin.Context) {})
}

func (a *APIRouter) RegisterAPIRouter(r *gin.RouterGroup) {
	r.GET("/ai/conversation", func(ctx *gin.Context) {})
	r.DELETE("/ai/conversation", func(ctx *gin.Context) {})
	questions := r.Group("/question")
	questions.POST("/report", func(ctx *gin.Context) {})
}

func (a *APIRouter) RegisterAdminAPIRouter(r *gin.RouterGroup) {
	r.PUT("/users/status", func(ctx *gin.Context) {})
}
