package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// Separate handler function
func healthHandler(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func setupAdditionalRoutes(r *gin.Engine) {
	// PATCH method test
	r.PATCH("/items/:id", func(c *gin.Context) {
		c.JSON(http.StatusOK, nil)
	})

	// Multiple query params
	r.GET("/search", func(c *gin.Context) {
		_ = c.Query("q")
		_ = c.DefaultQuery("page", "1")
		_ = c.Query("limit")
		c.JSON(http.StatusOK, nil)
	})

	// Handler reference (non-inline)
	r.GET("/healthz", healthHandler)

	// Deeply nested groups
	api := r.Group("/api")
	v2 := api.Group("/v2")
	v2.POST("/data", func(c *gin.Context) {
		_ = c.PostForm("payload")
		c.JSON(http.StatusOK, nil)
	})

	// POST with header extraction
	r.POST("/webhook", func(c *gin.Context) {
		_ = c.GetHeader("X-Webhook-Secret")
		_ = c.PostForm("event")
		c.JSON(http.StatusOK, nil)
	})

	// Cookie extraction
	r.GET("/profile", func(c *gin.Context) {
		_ = c.Cookie("session_id")
		_ = c.Query("tab")
		c.JSON(http.StatusOK, nil)
	})
}
