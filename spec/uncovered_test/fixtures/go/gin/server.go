package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

func main() {
	r := gin.Default()

	// c.Param() for path parameters - not detected by gin analyzer
	// Gin analyzer only detects Query, PostForm, GetHeader, Cookie
	r.GET("/users/:id", func(c *gin.Context) {
		_ = c.Param("id")
		c.JSON(http.StatusOK, nil)
	})

	// c.ShouldBindJSON - not detected by gin analyzer
	r.POST("/data", func(c *gin.Context) {
		var body map[string]interface{}
		c.ShouldBindJSON(&body)
		c.JSON(http.StatusOK, nil)
	})

	r.Run()
}
