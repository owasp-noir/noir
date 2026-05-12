package main

import (
	"github.com/valyala/fasthttp"
)

// Minimal router stub mirroring the verb-method shape `extract_routes`
// recognises for fasthttp (`<router>.GET("/path", handler)` etc.).
type Router struct{}

func (r *Router) GET(path string, handler func(*fasthttp.RequestCtx))  {}
func (r *Router) POST(path string, handler func(*fasthttp.RequestCtx)) {}

func main() {
	router := &Router{}
	router.POST("/users", createUser)
	router.GET("/healthz", func(ctx *fasthttp.RequestCtx) {
		ctx.WriteString("ok")
	})
	router.GET("/profile", listProfile)
	fasthttp.ListenAndServe(":8080", nil)
}
