package main

import (
	"os"

	"github.com/gin-gonic/gin"

	"example.com/builderpkg/routes"
)

func main() {
	r := gin.Default()
	api := r.Group("/api/v1")
	routes.RegisterUsers(api)
	routes.RegisterPosts(api.Group("/posts"))
	addHealth(api.Group("/health"))
	const publicPath = "/public"
	routes.RegisterEvents(r.Group(publicPath))
	ops := r.Group(configuredPath("OPERATIONS_PATH", "/ops"))
	routes.RegisterEvents(ops)
	routes.RegisterEvents(r.Group(os.Getenv("REGIONAL_PATH")))
	routes.Preview(r.Group("/sample"))
	r.Run()
}

func addHealth(rg *gin.RouterGroup) {
	rg.GET("/live", func(c *gin.Context) {})
}

func configuredPath(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
