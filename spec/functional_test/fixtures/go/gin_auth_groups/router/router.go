package router

import (
	"example.com/app/auth"
	"example.com/app/mw"
	"github.com/gin-gonic/gin"
)

func h(c *gin.Context) {}

func Create() *gin.Engine {
	r := gin.New()

	authed := r.Group("/api")
	early := authed.Group("/early")
	authed.Use(mw.AuthRequired())
	authed.GET("/plain", h)
	authed.GET("/plain2", h)
	authed.GET("/plain3", h)
	authed.GET("/plain4", h)
	authed.GET("/plain5", h)
	authed.GET("/plain6", h)
	authed.Group("/x").Use(mw.RateLimit()).GET("/chained", h)
	early.GET("/c", h)

	g2 := r.Group("/v2", mw.AuthRequired())
	g2.GET("/direct", h)
	g2.Group("/y").Use(mw.RateLimit()).GET("/chained2", h)

	a := auth.Auth{}
	three := r.Group("/three")
	three.Use(a.RequireLogin)
	three.GET("/x", h)
	four := r.Group("/four")
	four.Use(a.RequireToken)
	four.GET("/x", h)
	return r
}

func Private(r *gin.Engine) {
	{
		base := r.Group("")
		base.Use(mw.AuthRequired())
		sub := base.Group("/app")
		sub.GET("/a1", h)
		sub.GET("/a2", h)
		sub.GET("/a3", h)
		sub.GET("/a4", h)
		sub.GET("/a5", h)
		sub.GET("/a6", h)
		sub.GET("/a7", h)
	}
}

func Public(r *gin.Engine) {
	pub := r.Group("")
	sub := pub.Group("/app")
	sub.GET("/p1", h)
}
