package main

import (
	"context"

	"github.com/cloudwego/hertz/pkg/app"
)

func createUser(c context.Context, ctx *app.RequestContext) {
	name := ctx.PostForm("name")
	user := saveUser(string(name))
	auditLog(user)
	ctx.JSON(200, map[string]string{"id": user})
}

func listProfile(c context.Context, ctx *app.RequestContext) {
	data := buildProfile()
	auditLog(data)
	ctx.JSON(200, data)
}
