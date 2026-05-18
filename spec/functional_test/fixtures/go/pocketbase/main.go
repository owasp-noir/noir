// Regression fixture: a Pocketbase app uses
// `github.com/pocketbase/pocketbase/tools/router` and registers
// routes via the framework's RouterGroup API. The DSL mirrors
// Echo/Gin; the analyzer just gates on the import marker.
package main

import (
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
)

func bindFooApi(app core.App, rg *router.RouterGroup[*core.RequestEvent]) {
	sub := rg.Group("/foos")
	sub.GET("", listFoos)
	sub.POST("", createFoo)
	sub.GET("/{id}", getFoo)
	sub.PATCH("/{id}", updateFoo)
	sub.DELETE("/{id}", deleteFoo)
}

func listFoos(e *core.RequestEvent) error   { return nil }
func createFoo(e *core.RequestEvent) error  { return nil }
func getFoo(e *core.RequestEvent) error     { return nil }
func updateFoo(e *core.RequestEvent) error  { return nil }
func deleteFoo(e *core.RequestEvent) error  { return nil }
