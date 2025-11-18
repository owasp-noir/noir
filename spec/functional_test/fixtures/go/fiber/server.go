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

	app.Get("/ws", websocket.New(func(c *websocket.Conn) {
		// Websocket logic
	}))

	mygroup := app.Group("/admin")
	mygroup.Get("/users", func(c *fiber.Ctx) error {
		return c.SendString(msg) // => ✋ register
	})

	v1 := mygroup.Group("/v1")
	v1.Get("/migration", func(c *fiber.Ctx) error {
		return c.SendString(msg) // => ✋ register
	})

	app.Static("/", "/public")
	
	// Test additional HTTP methods
	app.Put("/update-put", func(c *fiber.Ctx) error {
		return c.SendString("PUT")
	})
	
	app.Delete("/delete-item", func(c *fiber.Ctx) error {
		return c.SendString("DELETE")
	})
	
	// Multi-line route definition
	app.Get(
		"/multiline",
		func(c *fiber.Ctx) error {
			_ = c.Query("ml_param")
			return c.SendString("multiline")
		},
	)

	log.Fatal(app.Listen(":3000"))
}
