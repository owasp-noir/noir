// A stock PocketBase app (the documented extending-with-Go shape): it imports
// only `pocketbase` and `core`, never `tools/router`, and registers routes on
// the `se.Router` field inside the OnServe hook.
package main

import (
	"log"
	"net/http"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
)

func main() {
	app := pocketbase.New()

	app.OnServe().BindFunc(func(se *core.ServeEvent) error {
		se.Router.GET("/hello/{name}", func(e *core.RequestEvent) error {
			name := e.Request.PathValue("name")
			return e.String(http.StatusOK, "Hello "+name)
		})

		api := se.Router.Group("/api/custom")
		api.POST("/items", func(e *core.RequestEvent) error {
			return e.NoContent(http.StatusCreated)
		})

		return se.Next()
	})

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
