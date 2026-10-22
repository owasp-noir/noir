package main

import "github.com/gin-gonic/gin"

func main() {
	r := gin.Default()
	r.GET("/x", RateLimit(), listX)
	r.POST("/y", listY)
	r.GET("/z", func(c *gin.Context) {})
}

func RateLimit() gin.HandlerFunc { return nil }

func listX(c *gin.Context) {
	_ = c.Query("qx")
}

func listY(c *gin.Context) {
	_ = c.Query("qy")
}
