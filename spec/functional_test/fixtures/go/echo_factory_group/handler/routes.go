package handler

import "github.com/labstack/echo/v4"

type Handler struct{}

func NewHandler() *Handler { return &Handler{} }

func (h *Handler) ok(c echo.Context) error { return nil }

// Method builder, called as h.Register(v1).
func (h *Handler) Register(v1 *echo.Group) {
	users := v1.Group("/users")
	users.POST("/login", h.ok)
	v1.GET("/tags", h.ok)
}

// Group is the second argument, as in ut.NewHTTP(svc, v1).
func NewHTTP(h *Handler, v1 *echo.Group) {
	v1.GET("/me", h.ok)
}
