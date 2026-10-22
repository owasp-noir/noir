package main

import (
	"github.com/gin-gonic/gin"

	"example.com/builderpkg/routes"
)

func main() {
	r := gin.Default()
	api := r.Group("/api/v1")
	routes.RegisterUsers(api)
	routes.RegisterPosts(api.Group("/posts"))
	addHealth(api.Group("/health"))
	r.Run()
}

func addHealth(rg *gin.RouterGroup) {
	rg.GET("/live", func(c *gin.Context) {})
}
