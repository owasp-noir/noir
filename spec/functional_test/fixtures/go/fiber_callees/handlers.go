package main

import (
	"github.com/gofiber/fiber/v2"
)

func createUser(c *fiber.Ctx) error {
	name := c.FormValue("name")
	user := saveUser(name)
	auditLog(user)
	return c.JSON(map[string]string{"id": user})
}

func listProfile(c *fiber.Ctx) error {
	data := buildProfile()
	auditLog(data)
	return c.JSON(data)
}
