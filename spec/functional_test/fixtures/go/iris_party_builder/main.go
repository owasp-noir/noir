package main

import "github.com/kataras/iris/v12"

func main() {
	app := iris.New()
	v1 := app.Party("/api/v1")
	registerUsers(v1.Party("/users"))
	registerOrders(v1)
	_ = app.Listen(":8080")
}

func registerUsers(p iris.Party) {
	p.Get("/", h)
	p.Get("/{id:uint64}", h)
}

func registerOrders(p iris.Party) {
	p.Post("/orders", create)
}

func h(ctx iris.Context) {}

func create(ctx iris.Context) {
	_ = ctx.URLParam("dry_run")
}
