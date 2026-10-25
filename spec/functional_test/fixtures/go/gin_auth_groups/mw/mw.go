package mw

import "github.com/gin-gonic/gin"

func AuthRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.GetHeader("Authorization") == "" {
			c.AbortWithStatus(401)
			return
		}
		c.Next()
	}
}

func RateLimit() gin.HandlerFunc {
	return func(c *gin.Context) { c.Next() }
}
