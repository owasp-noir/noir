package routes

import (
	"github.com/kataras/iris/v12"
)

func Register(app *iris.Application) {
	api := app.Party("/api")
	v1 := api.Party("/v1")

	v1.Get("/users", func(ctx iris.Context) {
		_ = ctx.URLParam("search")
	})

	v1.Post("/users", func(ctx iris.Context) {
		var body map[string]interface{}
		ctx.ReadJSON(&body)
	})

	v1.Get("/profile", func(ctx iris.Context) {
		_ = ctx.GetHeader("Authorization")
		_ = ctx.GetCookie("session")
	})

	v1.Get("/files/{file:path}", func(ctx iris.Context) {})
}
