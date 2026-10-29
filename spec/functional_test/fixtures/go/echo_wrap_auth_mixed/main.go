package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/labstack/echo/v4"
)

const usersPath = "/users"

func echoRoutes() {
	e := echo.New()
	e.GET("/e/switch", listItems, authSwitch)
	e.GET("/e/csrfsess", listItems, authSessCSRF)
	g := e.Group("/e/grp", authSwitch)
	g.GET("/inside", listItems)
	e.GET(usersPath, withAuth(listItems))
	e.GET("/e/wrapped", withAuth(listItems))
}

func ginRoutes() {
	r := gin.Default()
	r.GET("/g/trailing", ginLog, ginWrap(ginMe))
	r.GET("/g/solo", ginWrap(ginMe))
	r.GET("/g/csrfsess", ginCSRFSess, ginMe)
}

func authSwitch(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c echo.Context) error {
		switch c.Path() {
		case "/health":
			return next(c)
		}
		if c.Request().Header.Get("Authorization") == "" {
			return c.NoContent(http.StatusUnauthorized)
		}
		return next(c)
	}
}

func csrfOK(c echo.Context) bool { return true }

func authSessCSRF(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c echo.Context) error {
		sess := c.Get("session")
		if sess == nil || !csrfOK(c) {
			return c.NoContent(http.StatusUnauthorized)
		}
		return next(c)
	}
}

func withAuth(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c echo.Context) error {
		if c.Request().Header.Get("Authorization") == "" {
			return c.NoContent(http.StatusUnauthorized)
		}
		return next(c)
	}
}

func ginLog(c *gin.Context) { c.Next() }

func ginWrap(next gin.HandlerFunc) gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.GetHeader("Authorization") == "" {
			c.AbortWithStatus(http.StatusUnauthorized)
			return
		}
		next(c)
	}
}

func ginCSRFSess(c *gin.Context) {
	if c.GetHeader("Cookie") == "" || c.GetHeader("X-CSRF-Token") == "" {
		c.AbortWithStatus(http.StatusUnauthorized)
		return
	}
	c.Next()
}

func ginMe(c *gin.Context) {}

func listItems(c echo.Context) error { return c.NoContent(http.StatusOK) }
