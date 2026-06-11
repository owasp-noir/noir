package main

import fiber "github.com/gofiber/fiber/v2"

type RouteRegistrar interface {
	Get(string, ...fiber.Handler) fiber.Router
	Post(string, ...fiber.Handler) fiber.Router
}

func main() {
	app := fiber.New()
	registerRoutes(app)
}

func getFeature(c *fiber.Ctx) error {
	return nil
}

func createFeature(c *fiber.Ctx) error {
	return nil
}
