package main

import (
	"fmt"

	"goyave.dev/goyave/v5"
)

func main() {
	server, err := goyave.New(goyave.Options{})
	if err != nil {
		fmt.Println(err)
		return
	}

	server.RegisterRoutes(func(server *goyave.Server, router *goyave.Router) {
		router.Post("/users", createUser)
		router.Get("/healthz", func(response *goyave.Response, request *goyave.Request) {
			response.JSON(200, map[string]bool{"ok": true})
		})
		router.Get("/profile", listProfile)
	})

	if err := server.Start(); err != nil {
		fmt.Println(err)
	}
}
