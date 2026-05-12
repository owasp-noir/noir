package main

import (
	"github.com/kataras/iris/v12"
)

func main() {
	app := iris.New()
	app.Post("/users", createUser)
	app.Get("/healthz", func(ctx iris.Context) {
		ctx.JSON(map[string]bool{"ok": true})
	})
	app.Get("/profile", listProfile)
	app.Listen(":8080")
}
