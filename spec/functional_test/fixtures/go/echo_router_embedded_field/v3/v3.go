package v3

import (
	"github.com/labstack/echo/v4"

	"example.com/echoembedded/legacy"
)

type Handler struct {
	*legacy.Base
}

// Not a route: the embedded `Echo` field is a `*legacy.Printer`.
func (h *Handler) register() {
	h.Echo.GET("/not-a-route-printer", h.noop)
}

func (h *Handler) noop() {}

func (h *Handler) ping(ctx echo.Context) error { return nil }
