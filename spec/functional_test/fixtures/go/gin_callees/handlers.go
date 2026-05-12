package main

import (
	"github.com/gin-gonic/gin"
)

func createUser(c *gin.Context) {
	name := c.PostForm("name")
	user := saveUser(name)
	auditLog(user)
	c.JSON(200, gin.H{"id": user})
}

func listProfile(c *gin.Context) {
	data := buildProfile()
	auditLog(data)
	c.JSON(200, data)
}
