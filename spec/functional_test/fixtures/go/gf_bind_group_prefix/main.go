package main

import (
	"github.com/gogf/gf/v2/frame/g"
	"github.com/gogf/gf/v2/net/ghttp"

	"example.com/gfbind/internal/controller"
)

func Auth(r *ghttp.Request) { r.Middleware.Next() }

func main() {
	s := g.Server()
	s.BindHandler("/hook", func(r *ghttp.Request) { r.Response.Write("ok") })
	s.Group("/api", func(group *ghttp.RouterGroup) {
		group.Middleware(Auth)
		group.Bind(controller.NewCtrl())
		group.ALL("/any", func(r *ghttp.Request) {})
	})
	s.Run()
}
