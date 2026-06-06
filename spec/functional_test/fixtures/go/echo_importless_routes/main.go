package main

import "github.com/labstack/echo/v4"

type RouteRegistrar interface {
	GET(string, echo.HandlerFunc, ...echo.MiddlewareFunc) *echo.Route
	POST(string, echo.HandlerFunc, ...echo.MiddlewareFunc) *echo.Route
}

func main() {
	e := echo.New()
	registerRoutes(e)
}

func getFeature(c echo.Context) error {
	return nil
}

func createFeature(c echo.Context) error {
	return nil
}
