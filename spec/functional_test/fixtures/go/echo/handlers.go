package main

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

// Separate handler functions (non-inline)
func getHealth(c echo.Context) error {
	return c.String(http.StatusOK, "OK")
}

func setupRoutes(e *echo.Echo) {
	// PATCH method test
	e.PATCH("/users/:id", func(c echo.Context) error {
		_ = c.Param("id")
		return c.NoContent(http.StatusOK)
	})

	// OPTIONS method test
	e.OPTIONS("/cors-check", func(c echo.Context) error {
		return c.NoContent(http.StatusOK)
	})

	// Multiple query params in one handler
	e.GET("/search", func(c echo.Context) error {
		_ = c.QueryParam("q")
		_ = c.QueryParam("page")
		_ = c.QueryParam("limit")
		return c.JSON(http.StatusOK, nil)
	})

	// Path param combined with query param
	e.GET("/items/:itemId/reviews", func(c echo.Context) error {
		_ = c.Param("itemId")
		_ = c.QueryParam("sort")
		return c.JSON(http.StatusOK, nil)
	})

	// Handler reference (non-inline)
	e.GET("/health", getHealth)

	// Deeply nested groups
	api := e.Group("/v2")
	admin := api.Group("/admin")
	admin.DELETE("/cache", func(c echo.Context) error {
		return c.NoContent(http.StatusOK)
	})
}
