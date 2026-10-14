package handlers

import "github.com/gin-gonic/gin"

func Create(c *gin.Context) {
	_ = c.PostForm("nickname")
}
