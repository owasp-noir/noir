package main

import (
	"github.com/kataras/iris/v12"
)

func createUser(ctx iris.Context) {
	name := ctx.PostValue("name")
	user := saveUser(name)
	auditLog(user)
	ctx.JSON(map[string]string{"id": user})
}

func listProfile(ctx iris.Context) {
	data := buildProfile()
	auditLog(data)
	ctx.JSON(data)
}
