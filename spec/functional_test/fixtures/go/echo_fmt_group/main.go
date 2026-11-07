package main

import (
	"fmt"
	"strings"

	"github.com/labstack/echo/v4"
)

// Pagoda's admin entities: the group segment is fmt.Sprintf, not a literal.
// The parent prefix (/admin/entity) has to survive, and RequireAdmin must
// not land on the public home route.
func main() {
	e := echo.New()
	e.GET("/", home)

	ag := e.Group("/admin", RequireAdmin)
	entities := ag.Group("/entity")
	name := "User"
	ng := entities.Group(fmt.Sprintf("/%s", strings.ToLower(name)))
	ng.GET("", list)
	ng.GET("/add", add)
	ng.GET("/:id/edit", edit)
}

func home(c echo.Context) error { return nil }
func list(c echo.Context) error { return nil }
func add(c echo.Context) error { return nil }
func edit(c echo.Context) error { return nil }

func RequireAdmin(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c echo.Context) error {
		if c.Get("user") == nil {
			return echo.NewHTTPError(http.StatusUnauthorized)
		}
		return next(c)
	}
}
