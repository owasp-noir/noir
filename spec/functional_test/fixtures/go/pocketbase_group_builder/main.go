package main

import (
	"log"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"

	"example.com/pbapp/apis"
)

func main() {
	app := pocketbase.New()
	app.OnServe().BindFunc(func(se *core.ServeEvent) error {
		api := se.Router.Group("/api")
		apis.BindBackupApi(app, api)
		apis.BindFirst(api)
		apis.BindSQL(api)
		api.GET("/direct", apis.H)
		return se.Next()
	})
	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
