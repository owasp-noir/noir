package main

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

func main() {
	e := echo.New()
	e.GET("/", func(c echo.Context) error {
		_ = c.Cookie("abcd_token")
		return c.String(http.StatusOK, "Hello, World!")
	})
	e.GET("/pet", func(c echo.Context) error {
		_ = c.QueryParam("query")
		_ = c.Request().Header.Get("X-API-Key")
		return c.String(http.StatusOK, "Hello, Pet!")
	})
	e.POST("/pet", func(c echo.Context) error {
		_ = c.Param("name")
		return c.String(http.StatusOK, "Hello, Pet!")
	})
	e.POST("/pet_form", func(c echo.Context) error {
		_ = c.FormValue("name")
		return c.String(http.StatusOK, "Hello, Pet!")
	})
	e.Static("/public", "public")
	e.Static("/public", "./public2")
	e.Static("/public", "/public3")

	e.Logger.Fatal(e.Start(":1323"))
}
