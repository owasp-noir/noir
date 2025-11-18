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
	mygroup := e.Group("/admin")
	mygroup.GET("/users", func(c echo.Context) error {
		return c.String(http.StatusOK, "Hello, Pet!")
	})

	v1 := mygroup.Group("/v1")
	v1.GET("/migration", func(c echo.Context) error {
		return c.String(http.StatusOK, "Hello, Pet!")
	})

	e.Static("/public", "public")
	e.Static("/public", "./public2")
	e.Static("/public", "/public3")
	
	// Test various coding styles
	// Mixed case methods (Go convention)
	e.Get("/mixed-get", func(c echo.Context) error {
		return c.String(http.StatusOK, "mixed case get")
	})
	
	e.Post("/mixed-post", func(c echo.Context) error {
		_ = c.FormValue("field1")
		return c.String(http.StatusOK, "mixed case post")
	})
	
	e.Put("/mixed-put", func(c echo.Context) error {
		return c.String(http.StatusOK, "mixed case put")
	})
	
	e.Delete("/mixed-delete", func(c echo.Context) error {
		return c.String(http.StatusOK, "mixed case delete")
	})
	
	// Multi-line route definition
	e.GET(
		"/multiline",
		func(c echo.Context) error {
			_ = c.QueryParam("ml_param")
			return c.String(http.StatusOK, "multiline")
		},
	)

	e.Logger.Fatal(e.Start(":1323"))
}
