package main

import (
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/csrf"
	"github.com/gofiber/fiber/v2/middleware/encryptcookie"
	"github.com/gofiber/fiber/v2/middleware/helmet"
	"github.com/gofiber/fiber/v2/middleware/limiter"
)

func main() {
	app := fiber.New()

	// Global Fiber security middleware — applies to every route.
	app.Use(helmet.New())
	app.Use(encryptcookie.New(encryptcookie.Config{Key: "secret-thirty-two-character-key!"}))

	app.Get("/status", func(c *fiber.Ctx) error {
		return c.SendString("ok")
	})

	// Rate-limited + CSRF-protected API group.
	api := app.Group("/api")
	api.Use(limiter.New())
	api.Use(csrf.New())
	api.Post("/orders", func(c *fiber.Ctx) error {
		return c.SendStatus(fiber.StatusCreated)
	})

	// CORS-enabled group.
	open := app.Group("/open")
	open.Use(cors.New())
	open.Get("/data", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{})
	})

	app.Listen(":3000")
}
