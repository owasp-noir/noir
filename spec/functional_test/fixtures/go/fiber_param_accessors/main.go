package main

import "github.com/gofiber/fiber/v2"

type Filter struct {
	Page   int    `query:"page"`
	Search string `query:"search"`
}

type CreateUser struct {
	Name  string `json:"name" form:"name"`
	Email string `json:"email" form:"email"`
}

type Hdr struct {
	Trace string `reqHeader:"X-Trace-Id"`
}

func main() {
	app := fiber.New()

	app.Get("/p01-typed-query", func(c *fiber.Ctx) error {
		_ = c.QueryInt("limit", 10)
		_ = c.QueryBool("active")
		_ = c.QueryFloat("ratio")
		return nil
	})
	app.Get("/p02-queryparser", func(c *fiber.Ctx) error {
		var f Filter
		return c.QueryParser(&f)
	})
	app.Post("/p03-bodyparser", func(c *fiber.Ctx) error {
		var u CreateUser
		return c.BodyParser(&u)
	})
	app.Get("/p04-cookie-default", func(c *fiber.Ctx) error {
		_ = c.Cookies("session", "none")
		return nil
	})
	app.Get("/p05-headerparser", func(c *fiber.Ctx) error {
		var h Hdr
		return c.ReqHeaderParser(&h)
	})
	app.Post("/p06-formfile", func(c *fiber.Ctx) error {
		_, _ = c.FormFile("document")
		return nil
	})
	_ = app.Listen(":3000")
}
