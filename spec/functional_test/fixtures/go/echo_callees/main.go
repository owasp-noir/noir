package main

import (
	"github.com/labstack/echo/v4"
)

func main() {
	e := echo.New()
	e.POST("/users", createUser)
	e.GET("/healthz", func(c echo.Context) error {
		return c.JSON(200, map[string]bool{"ok": true})
	})
	e.GET("/profile", listProfile)
	e.Start(":8080")
}
