package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

func setupRoutes(r *gin.Engine, v1 *gin.RouterGroup, admin *gin.RouterGroup, nested *gin.RouterGroup) {
	v1.GET("/users", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"users": "list"})
	})

	v1.POST("/users", func(c *gin.Context) {
		_ = c.PostForm("name")
		c.JSON(http.StatusOK, nil)
	})

	admin.GET("/dashboard", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"admin": "dashboard"})
	})

	nested.DELETE("/item", func(c *gin.Context) {
		c.JSON(http.StatusOK, nil)
	})
}
