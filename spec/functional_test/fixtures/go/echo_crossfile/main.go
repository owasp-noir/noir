package main

import (
	"github.com/labstack/echo/v4"
)

func main() {
	e := echo.New()

	api := e.Group("/api")
	v2 := api.Group("/v2")

	setupRoutes(e, api, v2)
	e.Logger.Fatal(e.Start(":8080"))
}
