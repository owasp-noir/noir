package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

func main() {
	r := gin.Default()
	r.GET("/ping", func(c *gin.Context) {
		_ = c.DefaultQuery("name", "Guest")
		_ = c.Query("age")

		c.JSON(http.StatusOK, gin.H{
			"message": "pong",
		})
	})
	r.GET("/admin", func(c *gin.Context) {
		_ = c.Cookie("abcd_token")
	})
	r.POST("/submit", func(c *gin.Context) {
		username := c.PostForm("username")
		password := c.DefaultPostForm("password", "default_password")
		userAgent := c.GetHeader("User-Agent")

		c.String(http.StatusOK, "Submitted data: Username=%s, Password=%s, userAgent=%s", username, password, userAgent)
	})

	users := r.Group("/group")
	users.GET("/users", func(c *gin.Context) {
		c.JSON(http.StatusOK, "users")
	})

	v1 := users.Group("/v1")
	v1.GET("/migration", func(c *gin.Context) {
		c.JSON(http.StatusOK, "users")
	})

	// Test various coding styles
	// Mixed case methods (Go convention)
	r.Get("/mixed-get", func(c *gin.Context) {
		c.JSON(http.StatusOK, "mixed case get")
	})
	
	r.Post("/mixed-post", func(c *gin.Context) {
		_ = c.PostForm("field1")
		c.JSON(http.StatusOK, "mixed case post")
	})
	
	r.Put("/mixed-put", func(c *gin.Context) {
		c.JSON(http.StatusOK, "mixed case put")
	})
	
	r.Delete("/mixed-delete", func(c *gin.Context) {
		c.JSON(http.StatusOK, "mixed case delete")
	})
	
	// Multi-line route definition
	r.GET(
		"/multiline",
		func(c *gin.Context) {
			_ = c.Query("ml_param")
			c.JSON(http.StatusOK, "multiline")
		},
	)

	r.Static("/public", "public")
	r.Run() // listen and serve on 0.0.0.0:8080 (for windows "localhost:8080")
}
