package mw

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

// Same name as b/mw.Wrap, but this one refuses anonymous callers.
func Wrap(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c echo.Context) error {
		if c.Request().Header.Get("Authorization") == "" {
			return c.NoContent(http.StatusUnauthorized)
		}
		return next(c)
	}
}
