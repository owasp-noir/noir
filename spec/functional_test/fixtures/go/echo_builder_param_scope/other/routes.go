package other

import "github.com/labstack/echo/v4"

type Module struct{ Name func() string }

func (m *Module) Register(group *echo.Group) {
	group.PUT("/import/"+m.Name()+"/upload", func(c echo.Context) error { return nil })
	group.GET("/other", func(c echo.Context) error { return nil })
}
