package routes

import (
	"example.com/echoscope/apiv2"
	"example.com/echoscope/mcp"

	"github.com/labstack/echo/v4"
)

func h(c echo.Context) error { return nil }

func RegisterRoutes(e *echo.Echo) {
	a := e.Group("/api/v1")
	registerAPIRoutes(a)
	a2 := e.Group(apiv2.GroupPrefix)
	registerAPIRoutesV2(e, a2)
}

func registerAPIRoutesV2(e *echo.Echo, a *echo.Group) {
	a.GET("/docs", h)
	a.GET("/ws", h)
	m := &mcp.Module{}
	m.Register(a)
}

func registerAPIRoutes(a *echo.Group) {
	a.GET("/info", h)
	u := a.Group("/user")
	u.GET("", h)
}
