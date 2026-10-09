package main

import "github.com/gofiber/fiber/v2"

func main() {
	app := fiber.New()
	app.Route("/r", func(router fiber.Router) {
		router.Get("/in", func(c *fiber.Ctx) error { return nil })
	})
	micro := fiber.New()
	micro.Get("/micro", func(c *fiber.Ctx) error { return nil })
	app.Mount("/mnt", micro)
	RegisterUsers(app.Group("/api"))
	app.Listen(":3000")
}

func RegisterUsers(r fiber.Router) {
	r.Get("/users", func(c *fiber.Ctx) error {
		_ = c.Query("page")
		return nil
	})
}
