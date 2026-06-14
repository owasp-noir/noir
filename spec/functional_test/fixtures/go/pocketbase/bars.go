// Second handler file in the same package that reuses the `sub` group
// variable name with a DIFFERENT prefix and attaches middleware via the
// fluent `.Bind(...)` / `.Unbind(...)` chain. Before the fix the chain
// blocked local prefix resolution, so `sub` fell back to a cross-file
// binding and `/foos`/`/bars` contaminated each other.
package main

import (
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
)

func bindBarApi(app core.App, rg *router.RouterGroup[*core.RequestEvent]) {
	sub := rg.Group("/bars").Bind(requireAuth()).Unbind("rateLimit")
	sub.GET("", listBars)
	sub.POST("", createBar)
	sub.DELETE("/{id}", deleteBar)
}

func requireAuth() string                 { return "" }
func listBars(e *core.RequestEvent) error  { return nil }
func createBar(e *core.RequestEvent) error { return nil }
func deleteBar(e *core.RequestEvent) error { return nil }
