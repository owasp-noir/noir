package v2

import (
	"net/http"

	"github.com/labstack/echo/v4"
	"github.com/spf13/viper"

	"example.com/echoembedded/core"
)

type Controller struct {
	*core.Controller
	client *http.Client
	cache  interface{ Get(key string, h func()) string }
}

func (c *Controller) initRoutes() {
	c.Echo.GET("/api/v2/audio/:id", c.audio)
	c.Group.GET("/health", c.health)
}

// None of these are routes.
func (c *Controller) lookups(ctx echo.Context, r *http.Request) {
	ctx.Request().Header.Get("/not-a-route-header")
	r.Header.Get("/not-a-route-request")
	c.client.Get("/not-a-route-client")
	c.Client.Get("/not-a-route-embedded-client")
	c.cache.Get("/not-a-route-cache", c.h)
	viper.Get("/not-a-route-viper")
}

func (c *Controller) h() {}

func (c *Controller) audio(ctx echo.Context) error {
	_ = ctx.QueryParam("format")
	return nil
}

func (c *Controller) health(ctx echo.Context) error { return nil }
