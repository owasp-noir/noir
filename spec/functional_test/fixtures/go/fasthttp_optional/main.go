package main

import (
	"github.com/fasthttp/router"
	"github.com/valyala/fasthttp"
)

func main() {
	r := router.New()
	// fasthttp/router path-parameter dialects that must normalize to
	// the canonical `{name}` placeholder.
	r.GET("/optional/{name?}", index)         // optional
	r.GET("/regex/{id:[0-9]+}", index)         // inline regex
	r.GET("/combo/{slug?:[a-z]+}", index)      // optional + regex
	fasthttp.ListenAndServe(":8080", r.Handler)
}

func index(ctx *fasthttp.RequestCtx) {
	_ = ctx.UserValue("name")
}
