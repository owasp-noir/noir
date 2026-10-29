package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// A login factory taking a callback, and a wrapper that only calls the
// handler it takes: neither guards.
func ginRoutes() {
	r := gin.Default()
	r.POST("/gin/login", ginLoginWith(checkPassword))
	r.GET("/gin/cb", withCallback(func(c *gin.Context) { c.Status(200) }))
}

func ginLoginWith(verify func(string) bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		if !verify(c.PostForm("password")) {
			c.AbortWithStatus(http.StatusUnauthorized)
			return
		}
		c.Status(http.StatusOK)
	}
}

func withCallback(fn func(*gin.Context)) gin.HandlerFunc {
	return func(c *gin.Context) {
		fn(c)
	}
}
