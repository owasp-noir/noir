// Regression guard: Go pins `*_test.go` to test-only builds —
// `go build` excludes them; only `go test` pulls them in. Real
// route handlers never live there, but echo/chi/gin's own
// `*_test.go` files register hundreds of router calls to
// exercise the framework. None of the URLs below should surface
// as endpoints in the functional spec.
package main

import (
	"net/http"
	"testing"

	"github.com/labstack/echo/v4"
)

func TestRoutes(t *testing.T) {
	e := echo.New()
	e.GET("/should-not-appear-test-get", func(c echo.Context) error {
		return c.String(http.StatusOK, "")
	})
	e.POST("/should-not-appear-test-post", func(c echo.Context) error {
		return c.String(http.StatusOK, "")
	})
}
