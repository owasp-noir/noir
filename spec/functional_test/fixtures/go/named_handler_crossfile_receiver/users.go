package main

import "github.com/gin-gonic/gin"

type UserCtl struct{}

var users = &UserCtl{}

func (u *UserCtl) List(c *gin.Context) {
	_ = c.Query("user_q")
}
