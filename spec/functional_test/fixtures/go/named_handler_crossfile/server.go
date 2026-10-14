package main

import "github.com/gin-gonic/gin"

func listSibling(c *gin.Context) {
	_ = c.Query("page")
}

func (s *Server) Show(c *gin.Context) {
	_ = c.GetHeader("X-Token")
}
