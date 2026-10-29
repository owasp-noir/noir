package main

import (
	"errors"
	"net/http"

	amw "example.com/adv/a/mw"
	"example.com/adv/b/mw"
	"github.com/labstack/echo/v4"
)

var ErrForbidden = errors.New("forbidden")
var ErrUnauthorized = errors.New("unauthorized")

type JWTConfig struct {
	Skipper func(c echo.Context) bool
}

type AuthOptions struct {
	Required bool
}

// Lookalikes of a guard wrapping the handler: none of these routes is
// guarded, except /dup2 (a/mw.Wrap refuses; b/mw.Wrap only passes on).
func main() {
	e := echo.New()
	e.GET("/csrf", withCSRF(listItems))
	e.GET("/errmap", handle(listItems))
	e.GET("/errmap2", handle2(listItems))
	e.POST("/login", loginWith(checkPassword))
	e.GET("/optstruct", listItems, requireAuthOpts(AuthOptions{Required: false}))
	e.GET("/dup", mw.Wrap(listItems))
	e.GET("/dup2", amw.Wrap(listItems))
	e.GET("/skip", listItems, JWTWithConfig(JWTConfig{Skipper: func(c echo.Context) bool { return true }}))
	e.POST("/login3", withLogging(func(c echo.Context) error {
		if c.FormValue("pw") != "x" {
			return c.NoContent(http.StatusUnauthorized)
		}
		return nil
	}))
	e.GET("/retry", withRetry(3, listItems))
	e.GET("/skipped", withSkip(listItems))
	e.GET("/open", listItems)
}

// CSRF check, not authentication.
func withCSRF(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c echo.Context) error {
		if c.Request().Header.Get("X-CSRF-Token") != "expected" {
			return c.NoContent(http.StatusForbidden)
		}
		return next(c)
	}
}

// Error mapper: the 403 is the handler's own error, after next ran.
func handle(fn func(echo.Context) error) echo.HandlerFunc {
	return func(c echo.Context) error {
		if err := fn(c); err != nil {
			if errors.Is(err, ErrForbidden) {
				return c.JSON(http.StatusForbidden, nil)
			}
			return c.JSON(http.StatusInternalServerError, nil)
		}
		return nil
	}
}

func handle2(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c echo.Context) error {
		err := next(c)
		if err == ErrUnauthorized {
			return c.NoContent(http.StatusUnauthorized)
		}
		return err
	}
}

// Login handler factory taking a password-check callback: wraps no handler.
func loginWith(verify func(string) bool) echo.HandlerFunc {
	return func(c echo.Context) error {
		if !verify(c.FormValue("password")) {
			return c.NoContent(http.StatusUnauthorized)
		}
		return c.NoContent(http.StatusOK)
	}
}

func checkPassword(p string) bool { return p == "x" }

func requireAuthOpts(opts AuthOptions) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			if opts.Required && c.Request().Header.Get("Authorization") == "" {
				return c.NoContent(http.StatusUnauthorized)
			}
			return next(c)
		}
	}
}

func JWTWithConfig(cfg JWTConfig) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			if cfg.Skipper != nil && cfg.Skipper(c) {
				return next(c)
			}
			if c.Request().Header.Get("Authorization") == "" {
				return c.NoContent(http.StatusUnauthorized)
			}
			return next(c)
		}
	}
}

func withLogging(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c echo.Context) error {
		return next(c)
	}
}

// Retries the handler; 403 only after the handler ran.
func withRetry(n int, next echo.HandlerFunc) echo.HandlerFunc {
	return func(c echo.Context) error {
		var err error
		for i := 0; i < n; i++ {
			if err = next(c); err == nil {
				return nil
			}
		}
		return c.NoContent(http.StatusForbidden)
	}
}

// Hands a health probe on early, then refuses anonymous callers: a guard
// (an early skip does not hand every request on).
func withSkip(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c echo.Context) error {
		if c.Path() == "/healthz" {
			return next(c)
		}
		if c.Request().Header.Get("Authorization") == "" {
			return c.NoContent(http.StatusUnauthorized)
		}
		return next(c)
	}
}

func listItems(c echo.Context) error { return c.NoContent(http.StatusOK) }
