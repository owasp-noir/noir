package main

import "github.com/kataras/iris/v12"

func listC(ctx iris.Context) {
	_ = ctx.URLParam("qc")
}

func main() {
	app := iris.New()
	app.Get("/a", listA)
	app.Get("/b", listB)
	app.Get("/c", listC)
	app.Listen(":8080")
}

func listA(ctx iris.Context) {
	_ = ctx.URLParam("qa")
}

func listB(ctx iris.Context) {
	_ = ctx.URLParam("qb")
}
