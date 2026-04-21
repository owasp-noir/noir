package main

import (
	"context"

	"github.com/cloudwego/hertz/pkg/app"
	"github.com/cloudwego/hertz/pkg/app/server"
)

func main() {
	h := server.Default()

	h.GET("/ping", func(c context.Context, ctx *app.RequestContext) {
		_ = ctx.DefaultQuery("name", "Guest")
		_ = ctx.Query("age")
		ctx.JSON(200, map[string]string{"message": "pong"})
	})

	h.POST("/submit", func(c context.Context, ctx *app.RequestContext) {
		_ = ctx.PostForm("username")
		_ = ctx.DefaultPostForm("password", "default")
		_ = ctx.GetHeader("User-Agent")
	})

	h.GET("/admin", func(c context.Context, ctx *app.RequestContext) {
		_, _ = ctx.Cookie("abcd_token")
	})

	// Any() registers the handler for every HTTP method.
	h.Any("/health", func(c context.Context, ctx *app.RequestContext) {
		ctx.String(200, "ok")
	})

	// Route groups
	api := h.Group("/group")
	api.GET("/users", func(c context.Context, ctx *app.RequestContext) {
		ctx.JSON(200, "users")
	})

	v1 := api.Group("/v1")
	v1.GET("/migration", func(c context.Context, ctx *app.RequestContext) {
		ctx.JSON(200, "v1 migration")
	})

	h.Static("/public", "./public")

	h.Spin()
}
