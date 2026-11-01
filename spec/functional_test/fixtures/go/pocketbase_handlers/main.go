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
		// A brace inside a string must not keep this closure open.
		se.Router.GET("/braces", func(e *core.RequestEvent) error {
			msg := fmt.Sprintf("{%s", e.Request.URL.Query().Get("open"))
			return e.String(200, msg)
		})
		se.Router.GET("/next", func(e *core.RequestEvent) error {
			return e.String(200, e.Request.URL.Query().Get("after"))
		})
		se.Router.GET("/one", func(e *core.RequestEvent) error { return e.String(200, e.Request.URL.Query().Get("q")) })
		// A route registered inside another route's closure.
		se.Router.GET("/outer", func(e *core.RequestEvent) error {
			se.Router.GET("/inner", func(e *core.RequestEvent) error {
				return e.String(200, e.Request.URL.Query().Get("deep"))
			})
			return e.String(200, e.Request.URL.Query().Get("shallow"))
		})
		return se.Next()
	})
	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
