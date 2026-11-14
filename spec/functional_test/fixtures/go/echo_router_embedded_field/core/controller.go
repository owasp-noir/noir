package core

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

type Controller struct {
	Echo   *echo.Echo
	Group  *echo.Group
	Client *http.Client
}

func New(e *echo.Echo) *Controller {
	return &Controller{Echo: e, Group: e.Group("/api/v2")}
}
