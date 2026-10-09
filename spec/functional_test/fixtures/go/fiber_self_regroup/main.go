package main

import "github.com/gofiber/fiber/v2"

// Package-level group set here and re-grouped from itself in routes.go:
// routes.go's `r = r.Group("/v1")` must stack onto this `/api`.
var r fiber.Router

func main() {
	app := fiber.New()
	r = app.Group("/api")
	setup()
	local(app)
	app.Listen(":3000")
}

// A local router re-grouped from itself must not stack its own prefix
// twice (`/a/a/y`).
func local(g fiber.Router) {
	g = g.Group("/a")
	g.Get("/y", h)
}

func h(c *fiber.Ctx) error { return nil }
