package main

import (
	"fmt"
	"net/http"

	"goyave.dev/goyave/v5"
	"goyave.dev/goyave/v5/util/fsutil/osfs"
)

func main() {
	server, err := goyave.New(goyave.Options{})
	if err != nil {
		fmt.Println(err)
		return
	}

	server.RegisterRoutes(func(server *goyave.Server, router *goyave.Router) {
		router.Get("/", func(response *goyave.Response, request *goyave.Request) {
			response.String(http.StatusOK, "Hello World")
		})

		router.Post("/create", func(response *goyave.Response, request *goyave.Request) {
			response.String(http.StatusCreated, "Created")
		})

        // Parameter example
        router.Get("/product/{id:[0-9]+}", func(response *goyave.Response, request *goyave.Request) {
            response.String(http.StatusOK, "Product")
        })

		// Subrouter example
		api := router.Subrouter("/api")
		api.Get("/users", func(response *goyave.Response, request *goyave.Request) {
			response.String(http.StatusOK, "Users")
		})

		// Group example
		v1 := api.Group()
		v1.Get("/version", func(response *goyave.Response, request *goyave.Request) {
			response.String(http.StatusOK, "v1")
		})

        // Static files
        router.Static(&osfs.FS{}, "/static", false)
	})

	if err := server.Start(); err != nil {
		fmt.Println(err)
	}
}
