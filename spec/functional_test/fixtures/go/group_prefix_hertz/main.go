package main

import (
	"context"

	"github.com/cloudwego/hertz/pkg/app"
	"github.com/cloudwego/hertz/pkg/app/server"
	"github.com/cloudwego/hertz/pkg/route"
)

func main() {
	h := server.Default()
	registerUsers(h.Group("/api/v1"))
	h.Spin()
}

func registerUsers(g *route.RouterGroup) {
	g.GET("/users", func(ctx context.Context, c *app.RequestContext) {
		_ = c.Query("page")
	})
}
