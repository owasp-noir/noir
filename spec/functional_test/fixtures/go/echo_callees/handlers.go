package main

import (
	"github.com/labstack/echo/v4"
)

func createUser(c echo.Context) error {
	name := c.FormValue("name")
	user := saveUser(name)
	auditLog(user)
	return c.JSON(200, map[string]string{"id": user})
}

func listProfile(c echo.Context) error {
	data := buildProfile()
	auditLog(data)
	return c.JSON(200, data)
}
