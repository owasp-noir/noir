package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

func main() {
	r := gin.Default()

	// Public routes
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	r.GET("/public", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"message": "public"})
	})

	// Auth middleware protected group
	api := r.Group("/api")
	api.Use(AuthMiddleware())
	api.GET("/profile", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"user": "profile"})
	})

	// Inline auth middleware
	r.GET("/dashboard", AuthRequired, func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"dashboard": true})
	})

	// Admin route with role check
	r.DELETE("/admin/users/:id", AdminOnly, func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"deleted": true})
	})

	r.Run(":8080")
}

// AuthMiddleware validates JWT tokens from the Authorization header.
// Simplified for fixture purposes — production code should verify token signature.
func AuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		token := c.GetHeader("Authorization")
		if token == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
			return
		}
		// TODO: validate token signature in production
		c.Next()
	}
}

func AuthRequired(c *gin.Context) {
	token := c.GetHeader("Authorization")
	if token == "" {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	c.Next()
}

func AdminOnly(c *gin.Context) {
	role := c.GetString("role")
	if role != "admin" {
		c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "forbidden"})
		return
	}
	c.Next()
}
