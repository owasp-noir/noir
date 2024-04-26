package main

import (
	"context"

	"github.com/beego/beego/v2/server/web"
)

func main() {
	web.Run()

	web.Get("/", func(ctx *context.Context) {
		ctx.Output.Body([]byte("hello world"))
	})

	web.Post("/alice", func(ctx *context.Context) {
		ctx.Output.Body([]byte("bob"))
	})
}
