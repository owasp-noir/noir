package main

import (
	"github.com/gogf/gf/v2/frame/g"
	"github.com/gogf/gf/v2/net/ghttp"
)

func main() {
	s := g.Server()

	s.BindHandler("/upload", func(r *ghttp.Request) {
		file := r.GetUploadFile("TestFile")
		if file == nil {
			r.Response.Write("empty file")
			return
		}
		r.Response.Write("ok")
	})

	s.BindHandler("/ping", func(r *ghttp.Request) {
		name := r.GetQuery("name")
		r.Response.Write("pong " + name.String())
	})

	s.BindHandler("/admin", func(r *ghttp.Request) {
		_ = r.Cookie.Get("abcd_token")
	})

	s.Group("/api", func(group *ghttp.RouterGroup) {
		group.GET("/users", func(r *ghttp.Request) {
			_ = r.GetQuery("status")
			r.Response.Write("users")
		})

		group.POST("/submit", func(r *ghttp.Request) {
			username := r.GetForm("username")
			password := r.Get("password")
			userAgent := r.GetHeader("User-Agent")

			r.Response.Writef("Submitted data: Username=%s, Password=%s, userAgent=%s", username, password, userAgent)
		})

		v1 := group.Group("/v1")
		v1.GET("/migration", func(r *ghttp.Request) {
			r.Response.Write("migration")
		})

		v1.PUT("/update", func(r *ghttp.Request) {
		    r.Response.Write("update")
		})
	})

	// Mixed case methods test
	s.Group("/mixed", func(group *ghttp.RouterGroup) {
		group.GET("/get", func(r *ghttp.Request) {
			r.Response.Write("mixed case get")
		})
		group.POST("/post", func(r *ghttp.Request) {
			_ = r.GetForm("field1")
			r.Response.Write("mixed case post")
		})
		group.DELETE("/delete", func(r *ghttp.Request) {
			r.Response.Write("mixed case delete")
		})
	})

	// Multi-line route definition
	s.Group("/multi").GET(
		"/line",
		func(r *ghttp.Request) {
			_ = r.GetQuery("ml_param")
			r.Response.Write("multiline")
		},
	)

	s.SetServerRoot("public")
	s.Run()
}
