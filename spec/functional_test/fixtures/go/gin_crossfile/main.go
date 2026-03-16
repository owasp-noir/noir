package main

import (
	"github.com/gin-gonic/gin"
)

func main() {
	r := gin.Default()

	v1 := r.Group("/v1")
	admin := r.Group("/admin")
	nested := v1.Group("/nested")

	setupRoutes(r, v1, admin, nested)
	r.Run()
}
