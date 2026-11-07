package main

import "github.com/gofiber/fiber/v2"

func Auth() fiber.Handler {
	return func(c *fiber.Ctx) error {
		_ = c.Get("Authorization")
		_ = c.Query("redirect")
		// Optional ownership check — only meaningful when :userId is in the path.
		_ = c.Params("userId")
		return c.Next()
	}
}

func listUsers(c *fiber.Ctx) error { return c.SendString("ok") }
func getUser(c *fiber.Ctx) error   { return c.SendString(c.Params("userId")) }
func sendEmail(c *fiber.Ctx) error { return c.SendString("ok") }

func main() {
	app := fiber.New()
	v1 := app.Group("/v1")
	users := v1.Group("/users")
	users.Get("/", Auth(), listUsers)      // path has NO :userId
	users.Get("/:userId", Auth(), getUser) // path HAS :userId
	v1.Post("/auth/send-verification-email", Auth(), sendEmail)
	app.Listen(":3000")
}
