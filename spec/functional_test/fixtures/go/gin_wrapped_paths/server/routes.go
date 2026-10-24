package server

import (
	"github.com/gin-gonic/gin"

	"example.com/wrapped/api"
	"example.com/wrapped/config"
)

// APIv1 is assigned in start.go.
var APIv1 *gin.RouterGroup

func registerRoutes(router *gin.Engine, conf *config.Config) {
	isLive := func(c *gin.Context) {
		c.String(200, "ok")
	}
	router.GET(conf.BaseUri("/livez"), isLive)
	router.GET(config.Versioned("/status"), func(c *gin.Context) {
		c.String(200, "ok")
	})

	s := router.Group(conf.BaseUri("/s"))
	api.ShareToken(s)

	api.GetPhoto(APIv1)
	api.GetVersion(APIv1)
}
