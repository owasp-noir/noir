package main

import (
	"log"

	fiber "github.com/gofiber/fiber/v2"
)

func main() {
	app := fiber.New()

	// GET /api/register
	app.Get("/info", func(c *fiber.Ctx) error {
		msg := c.Query("sort")
		return c.SendString(msg) // => ✋ register
	})

	app.Post("/update", func(c *fiber.Ctx) error {
		msg := "Hello, World!"
		c.Cookies("auth")
		c.FormValue("name")
		c.GetRespHeader("X-API-Key")
		c.Vary("Origin")
		return c.SendString(msg) // => ✋ register
	})

	app.Static("/", "/public")

	log.Fatal(app.Listen(":3000"))
}
