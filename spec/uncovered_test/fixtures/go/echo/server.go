package main

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

func main() {
	e := echo.New()

	// Regression guard: commented routes must not be detected.
	// e.GET("/old-route", func(c echo.Context) error {
	//     return c.String(http.StatusOK, "old")
	// })

	e.GET("/users/:id", func(c echo.Context) error {
		_ = c.Param("id")
		return c.String(http.StatusOK, "user")
	})

	e.Logger.Fatal(e.Start(":1323"))
}
