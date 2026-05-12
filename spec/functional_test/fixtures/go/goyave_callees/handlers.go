package main

import (
	"goyave.dev/goyave/v5"
)

func createUser(response *goyave.Response, request *goyave.Request) {
	name := request.QueryParams.Get("name")
	user := saveUser(name)
	auditLog(user)
	response.JSON(200, map[string]string{"id": user})
}

func listProfile(response *goyave.Response, request *goyave.Request) {
	data := buildProfile()
	auditLog(data)
	response.JSON(200, data)
}
