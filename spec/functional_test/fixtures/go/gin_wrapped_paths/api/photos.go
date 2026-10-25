package api

import (
	"github.com/gin-gonic/gin"
)

func GetPhoto(router *gin.RouterGroup) {
	router.GET("/photos/:uid", func(c *gin.Context) {
		s := Auth(c)

		if s.Abort(c) {
			return
		}

		c.JSON(200, c.Param("uid"))
	})
}

func GetVersion(router *gin.RouterGroup) {
	router.GET("/version", func(c *gin.Context) {
		if logged(c) {
			return
		}

		c.JSON(200, "v1")
	})
}

func ShareToken(router *gin.RouterGroup) {
	router.GET("/:token", func(c *gin.Context) {
		c.JSON(200, c.Param("token"))
	})
}
