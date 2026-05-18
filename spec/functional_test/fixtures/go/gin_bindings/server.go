package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

func main() {
	r := gin.Default()

	r.GET("/users/:id", func(c *gin.Context) {
		_ = c.Param("id")
		c.JSON(http.StatusOK, nil)
	})

	r.POST("/data", func(c *gin.Context) {
		var body map[string]interface{}
		c.ShouldBindJSON(&body)
		c.JSON(http.StatusOK, nil)
	})

	r.Run()
}
