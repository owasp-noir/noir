package main

import (
	"log"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"

	"example.com/pbhandlers/apis"
)

func main() {
	app := pocketbase.New()
	app.OnServe().BindFunc(func(se *core.ServeEvent) error {
		api := se.Router.Group("/api")
		apis.BindFileApi(app, api)
		se.Router.GET("/hello", func(e *core.RequestEvent) error {
			name := e.Request.URL.Query().Get("name")
			return e.String(200, "hello "+name)
		})
		return se.Next()
	})
	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
