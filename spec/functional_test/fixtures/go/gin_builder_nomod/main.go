package main

import (
	"example.com/shop/controllers"
	"github.com/gin-gonic/gin"
)

func main() {
	r := gin.Default()
	r.POST("/incoming", controllers.Receive)
	api := r.Group("/api")
	controllers.RegisterProductRoutes(api.Group("/products"))
}
