package main

import (
	"github.com/gofiber/fiber/v2"
)

func main() {
	app := fiber.New()
	app.Post("/users", createUser)
	app.Get("/healthz", func(c *fiber.Ctx) error {
		return c.JSON(map[string]bool{"ok": true})
	})
	app.Get("/profile", listProfile)
	app.Listen(":8080")
}
