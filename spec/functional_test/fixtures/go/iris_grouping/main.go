// Iris route-registration shapes beyond the plain verb form:
//   - app.Handle("METHOD", "/path", h)     method-first registration
//   - app.HandleMany("GET POST", ...)       several verbs at once
//   - app.PartyFunc("/x", func(p){...})     closure-scoped group
//   - app.Party("/x", func(p){...})         closure form of Party
//   - nested PartyFunc inside a PartyFunc closure
package main

import "github.com/kataras/iris/v12"

func main() {
	app := iris.New()

	app.Handle("GET", "/handle-get", h)
	app.Handle("DELETE", "/handle-del", h)

	app.HandleMany("GET POST", "/many", h)

	app.PartyFunc("/pf", func(p iris.Party) {
		p.Get("/inside", h)
		p.Post("/create", h)

		// Nested group: prefix should stack to /pf/admin/stats.
		p.PartyFunc("/admin", func(a iris.Party) {
			a.Get("/stats", h)
		})
	})

	app.Party("/pc", func(p iris.Party) {
		p.Get("/x", h)
	})

	// Subdomain party: `admin.` is a host, not a path segment — the
	// route path must stay clean (`/settings`), not `/admin./settings`.
	admin := app.Party("admin.")
	admin.Get("/settings", h)

	app.Listen(":8080")
}

func h(ctx iris.Context) {}
