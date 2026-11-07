package main

import (
	"context"

	"github.com/beego/beego/v2/server/web"
)

func main() {
	web.Run()

	web.Get("/", func(ctx *context.Context) {
		ctx.GetString("lang", "en")
		ctx.Output.Body([]byte("hello world"))
	})

	web.Post("/alice", func(ctx *context.Context) {
		ctx.GetCookie("auth")
		// GetStrings reads Request.Form, so this is a body field on POST.
		ctx.GetStrings("query")
		ctx.Output.Body([]byte("bob"))
	})
}
