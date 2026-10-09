package main

import (
	"github.com/beego/beego/v2/server/web"
	"github.com/beego/beego/v2/server/web/context"
)

func listC(ctx *context.Context) {
	_ = ctx.Input.GetString("qc")
}

func main() {
	web.Get("/a", listA)
	web.Get("/b", listB)
	web.Get("/c", listC)
	web.Run()
}

func listA(ctx *context.Context) {
	_ = ctx.Input.GetString("qa")
}

func listB(ctx *context.Context) {
	_ = ctx.Input.GetString("qb")
}
