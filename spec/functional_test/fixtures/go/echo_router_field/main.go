package main

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

type App struct {
	*echo.Echo
	srv    *echo.Echo
	users  *echo.Group
	client *http.Client
}

func (a *App) routes() {
	a.srv.GET("/health", a.health)
	a.Echo.POST("/embedded", a.health)
	a.users = a.srv.Group("/users")
	a.users.GET("/:id", a.user)
	// Not routes.
	a.client.Get("/not-a-route")
}

func (a *App) health(c echo.Context) error { return nil }

func (a *App) user(c echo.Context) error {
	_ = c.Param("id")
	_ = c.QueryParam("fields")
	return nil
}

func main() {
	e := echo.New()
	a := &App{Echo: e, srv: e}
	a.routes()
	e.Start(":8080")
}
