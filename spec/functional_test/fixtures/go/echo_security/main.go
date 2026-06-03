package main

import (
	"net/http"
	"time"

	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
)

func main() {
	e := echo.New()

	// Global security middleware — applies to every route.
	e.Use(middleware.Secure())
	e.Use(middleware.RateLimiter(middleware.NewRateLimiterMemoryStore(20)))

	// Public route (inherits the global Secure + RateLimiter).
	e.GET("/health", func(c echo.Context) error {
		return c.String(http.StatusOK, "OK")
	})

	// CSRF-protected group.
	web := e.Group("/web")
	web.Use(middleware.CSRF())
	web.POST("/transfer", func(c echo.Context) error {
		return c.NoContent(http.StatusOK)
	})

	// Body-size cap on an upload group.
	upload := e.Group("/upload")
	upload.Use(middleware.BodyLimit("2M"))
	upload.POST("/file", func(c echo.Context) error {
		return c.NoContent(http.StatusOK)
	})

	// Timeout-guarded API group.
	api := e.Group("/api")
	api.Use(middleware.TimeoutWithConfig(middleware.TimeoutConfig{Timeout: 5 * time.Second}))
	api.GET("/report", func(c echo.Context) error {
		return c.NoContent(http.StatusOK)
	})

	// CORS-enabled (permissive) group.
	pub := e.Group("/pub")
	pub.Use(middleware.CORSWithConfig(middleware.CORSConfig{
		AllowOrigins: []string{"*"},
	}))
	pub.GET("/feed", func(c echo.Context) error {
		return c.NoContent(http.StatusOK)
	})

	// Inline route-level CSRF middleware (trailing arg on the route call).
	e.POST("/admin/reset", func(c echo.Context) error {
		return c.NoContent(http.StatusOK)
	}, middleware.CSRF())

	e.Logger.Fatal(e.Start(":8080"))
}
