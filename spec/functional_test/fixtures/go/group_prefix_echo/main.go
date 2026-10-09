package main

import "github.com/labstack/echo/v4"

func main() {
	e := echo.New()
	RegisterUsers(e.Group("/api/v1"))
	e.Start(":8080")
}

func RegisterUsers(g *echo.Group) {
	g.GET("/users", func(c echo.Context) error {
		_ = c.QueryParam("page")
		return nil
	})
}
