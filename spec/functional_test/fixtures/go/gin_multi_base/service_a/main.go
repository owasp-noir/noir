package main

import "github.com/gin-gonic/gin"

func main() {
	r := gin.Default()
	r.GET("/a-only", func(c *gin.Context) {})
	r.Static("/assets", "./public")
}
