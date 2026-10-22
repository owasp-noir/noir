package main

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

// The Go module does not sit at the scan base: the base is the monorepo
// root and this service lives two directories down. Both static
// registrations name paths relative to THIS file, which is what the
// analyzer has to resolve them against.
func main() {
	e := echo.New()

	e.GET("/health", func(c echo.Context) error {
		return c.String(http.StatusOK, "ok")
	})

	// Directory form.
	e.Static("/public", "public")

	// Single-file form — the one that used to be lost unless the scan base
	// happened to be this directory.
	e.File("/robots.txt", "static/robots.txt")

	e.Logger.Fatal(e.Start(":1323"))
}
