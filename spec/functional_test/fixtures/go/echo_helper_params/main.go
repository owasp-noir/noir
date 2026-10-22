package main

import "github.com/labstack/echo/v4"

type Keeper struct{}

func routes(e *echo.Echo) {
	g := e.Group("/keepers")
	g.GET("/list", guard(func(c echo.Context, k Keeper) error { return listAnimals(c) }))
	g.POST("/feed", guard(func(c echo.Context, k Keeper) error { return feedAnimal(c) }))
	g.DELETE("/cages/:cage", guard(func(c echo.Context, k Keeper) error { return c.NoContent(204) }))
	e.GET("/birds", func(c echo.Context) error { return c.String(200, c.QueryParam("color")) })
}

func guard(next func(echo.Context, Keeper) error) echo.HandlerFunc {
	return func(c echo.Context) error {
		tok := c.Request().Header.Get("X-Keeper-Token")
		_ = tok
		return next(c, Keeper{})
	}
}

func listAnimals(c echo.Context) error {
	page := c.QueryParam("page")
	return c.String(200, page)
}

func feedAnimal(c echo.Context) error {
	var b struct{ Food string }
	c.Bind(&b)
	enc := c.Param("enclosure")
	return c.String(200, enc)
}

func unused(c echo.Context) error {
	return c.String(200, c.QueryParam("orphan"))
}

func main() {
	e := echo.New()
	routes(e)
	e.Logger.Fatal(e.Start(":1323"))
}
