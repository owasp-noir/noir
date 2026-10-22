package main

import "github.com/gin-gonic/gin"

type server struct{}

func (s *server) List(c *gin.Context) {
	_ = c.Query("server_only")
}

func main() {
	r := gin.Default()
	r.GET("/users", users.List)
	r.GET("/other", func(c *gin.Context) {})
}
