package main

import (
	"context"

	"github.com/cloudwego/hertz/pkg/app"
	"github.com/cloudwego/hertz/pkg/app/server"
)

func main() {
	h := server.Default()
	h.POST("/users", createUser)
	h.GET("/healthz", func(c context.Context, ctx *app.RequestContext) {
		ctx.JSON(200, map[string]bool{"ok": true})
	})
	h.GET("/profile", listProfile)
	h.Spin()
}
