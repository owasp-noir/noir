package handler

import "github.com/labstack/echo/v4"

type Handler struct{}

func NewHandler() *Handler { return &Handler{} }

func (h *Handler) ok(c echo.Context) error { return nil }

// A router builder declared as a method, called as `h.Register(v1)`.
func (h *Handler) Register(v1 *echo.Group) {
	users := v1.Group("/users")
	users.POST("/login", h.ok)
	v1.GET("/tags", h.ok)
}

// The group is the second argument.
func RegisterAdmin(h *Handler, g *echo.Group) {
	g.GET("/stats", h.ok)
}

func localGroup(e *echo.Echo) {
	nearby := e.Group("/local")
	nearby.GET("/ready", func(c echo.Context) error { return nil })
}

func RegisterOptional(nearby *echo.Group) {
	nearby.GET("/optional", func(c echo.Context) error { return nil })
}

func firstGroup(e *echo.Echo) {
	branch := e.Group("/first")
	branch.GET("/earlier", func(c echo.Context) error { return nil })
}

func secondGroup(e *echo.Echo) {
	branch := e.Group("/second")
	branch.GET("/later", func(c echo.Context) error { return nil })
}
