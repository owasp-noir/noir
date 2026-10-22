package main

import (
	"github.com/gin-gonic/gin"

	"example.com/crossfile/handlers"
)

type Server struct{}

func main() {
	r := gin.Default()
	s := &Server{}
	r.GET("/sibling", listSibling)
	r.GET("/method", s.Show)
	r.POST("/imported", handlers.Create)
	r.GET("/last", func(c *gin.Context) {})
	r.Run()
}
