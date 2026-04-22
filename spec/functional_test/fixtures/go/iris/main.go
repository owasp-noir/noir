package main

import (
	"github.com/kataras/iris/v12"
)

func main() {
	app := iris.New()

	app.Get("/ping", func(ctx iris.Context) {
		_ = ctx.URLParam("name")
		_ = ctx.URLParam("age")
	})

	app.Post("/submit", func(ctx iris.Context) {
		_ = ctx.PostValue("username")
		_ = ctx.FormValue("email")
	})

	app.Put("/users/{id:uint64}", func(ctx iris.Context) {})
	app.Delete("/users/{id}", func(ctx iris.Context) {})
	app.Patch("/items/{id:uint64}", func(ctx iris.Context) {})
	app.Options("/health", func(ctx iris.Context) {})
	app.Head("/health", func(ctx iris.Context) {})

	app.Any("/any", func(ctx iris.Context) {})

	app.Listen(":8080")
}
