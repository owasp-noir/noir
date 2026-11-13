package router

import "github.com/gin-gonic/gin"

type PluginRouter struct{}

func (p *PluginRouter) RegisterConnectorRouter(r *gin.RouterGroup) {
	r.GET("/connector/info", func(ctx *gin.Context) {})
}

func (p *PluginRouter) RegisterUserCenterRouter(r *gin.RouterGroup) {
	r.GET("/user-center/agent", func(ctx *gin.Context) {})
}
