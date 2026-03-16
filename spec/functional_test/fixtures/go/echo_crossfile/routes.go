package main

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

func setupRoutes(e *echo.Echo, api *echo.Group, v2 *echo.Group) {
	api.GET("/health", func(c echo.Context) error {
		return c.JSON(http.StatusOK, map[string]string{"status": "ok"})
	})

	v2.POST("/data", func(c echo.Context) error {
		_ = c.FormValue("payload")
		return c.JSON(http.StatusOK, nil)
	})

	v2.GET("/items", func(c echo.Context) error {
		return c.JSON(http.StatusOK, nil)
	})
}
