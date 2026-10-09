package main

import (
	"context"

	"github.com/cloudwego/hertz/pkg/app"
	"github.com/cloudwego/hertz/pkg/app/server"
)

func listC(c context.Context, ctx *app.RequestContext) {
	_ = ctx.Query("qc")
}

func main() {
	h := server.Default()
	h.GET("/a", listA)
	h.GET("/b", listB)
	h.GET("/c", listC)
	h.Spin()
}

func listA(c context.Context, ctx *app.RequestContext) {
	_ = ctx.Query("qa")
}

func listB(c context.Context, ctx *app.RequestContext) {
	_ = ctx.Query("qb")
}
