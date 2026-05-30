package main

import "github.com/gin-gonic/gin"

func registerRoutes(r *gin.Engine) {
	v1 := r.Group("/api/v1")
	registerSysJobRouter(v1)
}
