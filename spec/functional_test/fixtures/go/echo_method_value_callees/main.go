package main

import (
	"net/http"
	"os"

	"github.com/labstack/echo/v4"
)

type ContactHandler struct{}

func (h *ContactHandler) Register(g *echo.Group) {
	g.GET("/:id/card", h.card)
	g.DELETE("/:id", h.remove)
}

func (h *ContactHandler) card(c echo.Context) error {
	data, err := os.ReadFile("/var/cards/" + c.Param("id"))
	if err != nil {
		return echo.ErrNotFound
	}
	return c.Blob(http.StatusOK, "text/vcard", data)
}

func (h *ContactHandler) remove(c echo.Context) error {
	os.Remove("/var/cards/" + c.Param("id"))
	return c.NoContent(http.StatusNoContent)
}

func main() {
	e := echo.New()
	contacts := e.Group("/contacts")
	(&ContactHandler{}).Register(contacts)
	e.Logger.Fatal(e.Start(":1323"))
}
