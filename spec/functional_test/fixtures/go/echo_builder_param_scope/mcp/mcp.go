package mcp

import "github.com/labstack/echo/v4"

type Module struct{}

func (m *Module) handler(c echo.Context) error { return nil }

// Register mounts the MCP endpoint on the group it is handed.
func (m *Module) Register(g *echo.Group) {
	g.POST("/mcp", m.handler)
}
