package main

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

func main() {
	e := echo.New()

	// Commented-out route - should NOT be detected (currently a false positive)
	// e.GET("/old-route", func(c echo.Context) error {
	//     return c.String(http.StatusOK, "old")
	// })

	// Route with path param - c.Param() detected as "json" type instead of "path"
	e.GET("/users/:id", func(c echo.Context) error {
		_ = c.Param("id")
		return c.String(http.StatusOK, "user")
	})

	e.Logger.Fatal(e.Start(":1323"))
}
