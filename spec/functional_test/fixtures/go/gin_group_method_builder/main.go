package main

import (
	"github.com/gin-gonic/gin"

	"example.com/ginbuilder/handler"
)

func main() {
	r := gin.Default()
	v1 := r.Group("/api")
	h := handler.NewHandler()
	h.Register(v1)
	r.Run(":8080")
}
