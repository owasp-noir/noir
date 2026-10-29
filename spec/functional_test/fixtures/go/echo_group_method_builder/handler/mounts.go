package handler

import "github.com/labstack/echo/v4"

type Admin struct{ h *Handler }

type Billing struct{ h *Handler }

// Two types with a same-named builder method: a `x.Mount(g)` call site can't
// tell them apart, so neither takes a call-site prefix (and neither takes the
// other's).
func (a *Admin) Mount(g *echo.Group) {
	g.GET("/audit", a.h.ok)
}

func (b *Billing) Mount(g *echo.Group) {
	g.GET("/invoices", b.h.ok)
}
