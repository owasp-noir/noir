package main

import (
	"github.com/valyala/fasthttp"
)

func createUser(ctx *fasthttp.RequestCtx) {
	name := string(ctx.FormValue("name"))
	user := saveUser(name)
	auditLog(user)
	ctx.WriteString(user)
}

func listProfile(ctx *fasthttp.RequestCtx) {
	data := buildProfile()
	auditLog(data)
	ctx.WriteString(data)
}
