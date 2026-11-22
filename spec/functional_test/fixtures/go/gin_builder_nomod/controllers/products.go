package controllers

import "github.com/gin-gonic/gin"

func RegisterProductRoutes(router *gin.RouterGroup) {
	router.GET("/", func(c *gin.Context) {})
	router.GET("/:slug", func(c *gin.Context) {})
}

func Receive(c *gin.Context) {
	var in struct {
		Label string `json:"label"`
	}
	_ = c.BindJSON(&in)
}
