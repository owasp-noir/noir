package main

import (
	v1 "example.com/nestedbuilder/internal/v1"
	"github.com/gin-gonic/gin"
)

func main() {
	r := gin.Default()
	api := r.Group("/api")
	v1.Register(api.Group("/v1"))
	_ = r.Run()
}
