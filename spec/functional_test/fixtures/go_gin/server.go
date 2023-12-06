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

	r.Static("/public", "public")
	r.Run() // listen and serve on 0.0.0.0:8080 (for windows "localhost:8080")
}
