package main

import (
	"github.com/gogf/gf/v2/net/ghttp"
)

func createUser(r *ghttp.Request) {
	name := r.GetQuery("name")
	user := saveUser(name.String())
	auditLog(user)
	r.Response.Write(user)
}

func listProfile(r *ghttp.Request) {
	data := buildProfile()
	auditLog(data)
	r.Response.Write(data)
}
