package main

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

type route struct {
	method  string
	path    string
	handler echo.HandlerFunc
}

func main() {
	e := echo.New()
	routes := []route{
		{"GET", "/items", listItems},
		{http.MethodPost, "/items", createItem},
		{method: "DELETE", path: "/items/:id", handler: deleteItem},
	}
	for _, rt := range routes {
		e.Add(rt.method, rt.path, rt.handler)
	}
	e.Logger.Fatal(e.Start(":8080"))
}

func listItems(c echo.Context) error {
	_ = c.QueryParam("page")
	return nil
}
func createItem(c echo.Context) error { return nil }
func deleteItem(c echo.Context) error { return nil }
