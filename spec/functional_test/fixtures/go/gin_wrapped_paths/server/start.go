package server

import (
	"github.com/gin-gonic/gin"

	"example.com/wrapped/config"
)

func Start(conf *config.Config) {
	router := gin.New()
	APIv1 = router.Group(conf.BaseUri(config.ApiUri))
	registerRoutes(router, conf)
	router.Run()
}
