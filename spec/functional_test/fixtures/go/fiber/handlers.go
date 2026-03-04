package main

import (
	fiber "github.com/gofiber/fiber/v2"
)

// Separate handler function
func healthCheck(c *fiber.Ctx) error {
	return c.SendString("OK")
}

func setupAdditionalRoutes(app *fiber.App) {
	// PATCH method test
	app.Patch("/items/:id", func(c *fiber.Ctx) error {
		return c.SendString("updated")
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
		c.GetRespHeader("Content-Length")
		return c.SendString("uploaded")
	})
}
