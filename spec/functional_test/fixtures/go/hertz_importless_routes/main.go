package main

import (
	"context"

	"github.com/cloudwego/hertz/pkg/app"
	"github.com/cloudwego/hertz/pkg/app/server"
	"github.com/cloudwego/hertz/pkg/route"
)

type RouteRegistrar interface {
	GET(string, ...app.HandlerFunc) route.IRoutes
	POST(string, ...app.HandlerFunc) route.IRoutes
	Handle(string, string, ...app.HandlerFunc) route.IRoutes
}

func main() {
	h := server.Default()
	registerRoutes(h)
}

func getFeature(c context.Context, ctx *app.RequestContext) {
	ctx.JSON(200, "ok")
}

func createFeature(c context.Context, ctx *app.RequestContext) {
	ctx.JSON(200, "ok")
}

func updateFeature(c context.Context, ctx *app.RequestContext) {
	ctx.JSON(200, "ok")
}

func customMethodFeature(c context.Context, ctx *app.RequestContext) {
	ctx.JSON(200, "ok")
}
