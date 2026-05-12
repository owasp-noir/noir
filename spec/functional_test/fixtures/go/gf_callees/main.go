package main

import (
	"github.com/gogf/gf/v2/frame/g"
	"github.com/gogf/gf/v2/net/ghttp"
)

func main() {
	s := g.Server()
	s.BindHandler("/users", createUser)
	s.BindHandler("/healthz", func(r *ghttp.Request) {
		r.Response.Write("ok")
	})
	s.Group("/api", func(group *ghttp.RouterGroup) {
		group.GET("/profile", listProfile)
	})
	s.Run()
}
