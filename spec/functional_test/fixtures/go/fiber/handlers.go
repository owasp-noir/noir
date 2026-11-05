package main

import (
	fiber "github.com/gofiber/fiber/v2"
)

// Separate handler function
func healthCheck(c *fiber.Ctx) error {
	return c.SendString("OK")
}

func setupAdditionalRoutes(app *fiber.App) {
	// PATCH method test — exercises `c.Params("id")` path accessor.
	app.Patch("/items/:id", func(c *fiber.Ctx) error {
		_ = c.Params("id")
		return c.SendString("updated")
	})

	// JSON body binding via `c.BodyParser`.
	app.Post("/inventory", func(c *fiber.Ctx) error {
		var body map[string]interface{}
		_ = c.BodyParser(&body)
		return c.JSON(nil)
	})

	// Multiple query params
	app.Get("/search", func(c *fiber.Ctx) error {
		_ = c.Query("q")
		_ = c.Query("page")
		_ = c.Query("limit")
		return c.JSON(nil)
	})

	// Handler reference (non-inline)
	app.Get("/healthz", healthCheck)

	// Deeply nested groups
	api := app.Group("/api")
	v2 := api.Group("/v2")
	v2.Get("/status", func(c *fiber.Ctx) error {
		return c.SendString("v2 status")
	})

	// POST with form and header combined
	app.Post("/upload", func(c *fiber.Ctx) error {
		c.FormValue("file_name")
		c.Get("Content-Length")
		return c.SendString("uploaded")
	})
}

// One handler behind a route with the `:word` slot and one without it.
func registerShort(app *fiber.App) {
	app.Get("/short", resolveShort)
	app.Get("/short/:word", resolveShort)
}

func resolveShort(c *fiber.Ctx) error {
	word := c.Params("word")
	return c.Redirect(word)
}
