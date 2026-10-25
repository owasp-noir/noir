package main

import (
	"net/http"
	"path"

	"github.com/labstack/echo/v5"
	"github.com/test/echo-wrapped-handlers/models"
)

const uriAdmin = "/admin"

type App struct{}

func main() {
	e := echo.New()
	a := &App{}

	{
		g := e.Group("", requireUser)
		g.GET(path.Join(uriAdmin, "/notes/:id"), a.page(hasID(a.ViewNote)))
		g.PUT("/api/notes/:id", hasID(a.UpdateNote))
		g.POST("/api/notes", a.CreateNote, logRequest)
	}

	{
		g := e.Group("")
		g.POST(path.Join(uriAdmin, "/forgot"), a.page(a.ForgotPage))
		g.GET("/subscribe", a.Subscribe)
		g.POST("/subscribe", a.Subscribe)
		g.GET("/stats", a.Stats)
	}

	e.Start(":8080")
}

func requireUser(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c *echo.Context) error {
		if c.Request().Header.Get("X-User") == "" {
			return echo.ErrUnauthorized
		}
		return next(c)
	}
}

func logRequest(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c *echo.Context) error {
		return next(c)
	}
}

func hasID(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c *echo.Context) error {
		if c.Param("id") == "" {
			return echo.NewHTTPError(http.StatusBadRequest, "invalid ID")
		}
		return next(c)
	}
}

func (a *App) page(h echo.HandlerFunc) echo.HandlerFunc {
	return func(c *echo.Context) error {
		return h(c)
	}
}

func (a *App) ViewNote(c *echo.Context) error {
	return c.String(http.StatusOK, c.Param("tab"))
}

func (a *App) UpdateNote(c *echo.Context) error {
	var n models.Note
	if err := c.Bind(&n); err != nil {
		return err
	}
	return c.JSON(http.StatusOK, n)
}

func (a *App) CreateNote(c *echo.Context) error {
	req := struct {
		models.Base
		Title string `json:"title" form:"title"`
		Tags  []int  `json:"tags"`
	}{}
	if err := c.Bind(&req); err != nil {
		return err
	}
	return c.JSON(http.StatusOK, req)
}

func (a *App) ForgotPage(c *echo.Context) error {
	return a.doForgot(c)
}

func (a *App) doForgot(c *echo.Context) error {
	return c.String(http.StatusOK, c.FormValue("email"))
}

type subReq struct {
	Lists []string `query:"l" form:"l"`
	Note  string
}

func (a *App) Subscribe(c *echo.Context) error {
	var (
		confirm = c.FormValue("confirm")
		req     subReq
	)
	if err := c.Bind(&req); err != nil {
		return err
	}
	return c.String(http.StatusOK, confirm)
}

func (a *App) Stats(c *echo.Context) error {
	from := c.QueryParams().Get("from")
	return c.String(http.StatusOK, from+c.QueryParam("to")+c.QueryParam("interval"))
}
