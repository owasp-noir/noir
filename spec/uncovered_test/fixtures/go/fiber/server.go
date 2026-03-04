package main

import (
	fiber "github.com/gofiber/fiber/v2"
)

func main() {
	app := fiber.New()

	// c.Params() for path parameter extraction - not detected by fiber analyzer
	// Fiber analyzer only detects .Query() and .FormValue()
	app.Get("/users/:id", func(c *fiber.Ctx) error {
		_ = c.Params("id")
		return c.SendString("user")
	})

	// c.BodyParser for JSON body - not detected by fiber analyzer
	app.Post("/data", func(c *fiber.Ctx) error {
		var body map[string]interface{}
		c.BodyParser(&body)
		return c.JSON(nil)
	})

	app.Listen(":3000")
}
