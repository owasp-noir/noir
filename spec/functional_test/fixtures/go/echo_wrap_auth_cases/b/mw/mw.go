package mw

import "github.com/labstack/echo/v4"

// Only hands the request on.
func Wrap(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c echo.Context) error {
		return next(c)
	}
}
