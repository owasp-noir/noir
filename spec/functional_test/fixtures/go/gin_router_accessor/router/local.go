package router

import "github.com/gin-gonic/gin"

// Same-package accessors: a function and a method.
func init() {
	V1().GET("/status", status)
	s := &Server{}
	s.Admin().GET("/stats", status)
}

func status(c *gin.Context) {}
