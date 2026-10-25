package session

import "github.com/gin-gonic/gin"

func Require(c *gin.Context) {
	if c.GetHeader("Cookie") == "" {
		c.AbortWithStatus(401)
		return
	}
	c.Next()
}
