package main

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

type User struct{}

func echoRoutes() {
	e := echo.New()
	admin := e.Group("/admin")
	admin.GET("/users", withAdminAuth(func(c echo.Context, u User) error {
		return c.JSON(http.StatusOK, u)
	}))
	e.GET("/logged", withLogging(listItems))
	e.GET("/wrapped", echo.WrapHandler(http.HandlerFunc(legacy)))
	e.GET("/limited", withRateLimit(listItems))
	e.GET("/nested", withLogging(withAdminAuth(showUser)))
	e.POST("/login", loginHandler(nil))
	e.GET("/public", listItems)
}

func currentUser(c echo.Context) (User, bool) {
	return User{}, c.Request().Header.Get("Authorization") != ""
}

// Refuses an anonymous caller before calling the handler it wraps.
func withAdminAuth(next func(echo.Context, User) error) echo.HandlerFunc {
	return func(c echo.Context) error {
		user, ok := currentUser(c)
		if !ok {
			return c.JSON(http.StatusUnauthorized, nil)
		}
		return next(c, user)
	}
}

// Only logs, then hands the request on.
func withLogging(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c echo.Context) error {
		c.Logger().Info(c.Path())
		return next(c)
	}
}

// Refuses, but on a rate limit: not an auth guard.
func withRateLimit(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c echo.Context) error {
		if tooMany(c) {
			return c.NoContent(http.StatusTooManyRequests)
		}
		return next(c)
	}
}

// A handler factory whose 401 answers a bad password: wraps nothing.
func loginHandler(store interface{}) echo.HandlerFunc {
	return func(c echo.Context) error {
		if c.FormValue("password") != "secret" {
			return c.NoContent(http.StatusUnauthorized)
		}
		return c.NoContent(http.StatusOK)
	}
}

func tooMany(c echo.Context) bool { return false }

func listItems(c echo.Context) error { return c.NoContent(http.StatusOK) }

func showUser(c echo.Context, u User) error { return c.JSON(http.StatusOK, u) }

func legacy(w http.ResponseWriter, r *http.Request) {}
