package main

import "github.com/labstack/echo/v4"

func serveRoot(e *echo.Echo) {
	e.Static("/", ".")
}
