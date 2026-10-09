package main

import "github.com/gin-gonic/gin"

func listC(c *gin.Context) {
	_ = c.Query("qc")
}

func main() {
	r := gin.Default()
	r.GET("/a", listA)
	r.GET("/b", listB)
	r.GET("/c", listC)
	r.Run()
}

func listA(c *gin.Context) {
	_ = c.Query("qa")
}

func listB(c *gin.Context) {
	_ = c.Query("qb")
}
