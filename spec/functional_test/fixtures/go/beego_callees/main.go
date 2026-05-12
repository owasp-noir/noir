package main

import (
	"github.com/beego/beego/v2/server/web"
	beegoctx "github.com/beego/beego/v2/server/web/context"
)

func main() {
	web.Post("/users", createUser)
	web.Get("/healthz", func(ctx *beegoctx.Context) {
		ctx.Output.Body([]byte("ok"))
	})
	web.Get("/profile", listProfile)
	web.Run()
}
