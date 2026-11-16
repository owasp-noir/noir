package main

import (
	"github.com/gin-gonic/gin"

	"example.com/shop/handler"
)

func main() {
	r := gin.New()
	users := r.Group("/users")
	handler.NewUserHandler().RegisterRoutes(users)
	r.Run(":8080")
}
