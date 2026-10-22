package main

import "github.com/gofiber/fiber/v2"

func listC(c *fiber.Ctx) error {
	qc := c.Query("qc")
	_ = qc
	return nil
}

func main() {
	app := fiber.New()
	app.Get("/a", listA)
	app.Get("/b", listB)
	app.Get("/c", listC)
	app.Listen(":3000")
}

func listA(c *fiber.Ctx) error {
	qa := c.Query("qa")
	_ = qa
	return nil
}

func listB(c *fiber.Ctx) error {
	qb := c.Query("qb")
	_ = qb
	return nil
}
