package main

import (
	beegoctx "github.com/beego/beego/v2/server/web/context"
)

func createUser(ctx *beegoctx.Context) {
	name := ctx.Input.Query("name")
	user := saveUser(name)
	auditLog(user)
	ctx.Output.Body([]byte(user))
}

func listProfile(ctx *beegoctx.Context) {
	data := buildProfile()
	auditLog(data)
	ctx.Output.Body([]byte(data))
}
