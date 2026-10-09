package main

import (
	"github.com/fasthttp/router"
	"github.com/valyala/fasthttp"
)

func listC(ctx *fasthttp.RequestCtx) {
	_ = ctx.QueryArgs().Peek("qc")
}

func main() {
	r := router.New()
	r.GET("/a", listA)
	r.GET("/b", listB)
	r.GET("/c", listC)
	fasthttp.ListenAndServe(":8080", r.Handler)
}

func listA(ctx *fasthttp.RequestCtx) {
	_ = ctx.QueryArgs().Peek("qa")
}

func listB(ctx *fasthttp.RequestCtx) {
	_ = ctx.QueryArgs().Peek("qb")
}
