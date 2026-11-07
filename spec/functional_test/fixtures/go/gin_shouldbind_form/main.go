// `ShouldBind` follows the struct tags. Form-only tags are form params
// named by the tag; json is emitted when a `json` tag is present, or when
// the field is untagged (the exported name). `ShouldBindJSON` and
// `ShouldBindQuery` are unchanged.
package main

import "github.com/gin-gonic/gin"

type CreateTag struct {
	Name        string `form:"name" binding:"required"`
	Description string `form:"description" binding:"required"`
}

type CreateOrder struct {
	FirstName string `form:"first_name" json:"first_name"`
	Note      string
}

type Message struct {
	Title string `json:"title"`
	Body  string
}

type paging struct {
	Limit int `form:"limit"`
}

func main() {
	r := gin.Default()
	r.POST("/tags", createTag)
	r.GET("/tags", listTags)
	r.POST("/orders", createOrder)
	r.POST("/messages", createMessage)
	r.GET("/items", listItems)
}

func createTag(c *gin.Context) {
	var createForm CreateTag
	if err := c.ShouldBind(&createForm); err != nil {
		return
	}
	c.JSON(200, createForm)
}

func listTags(c *gin.Context) {
	var q CreateTag
	_ = c.ShouldBind(&q)
}

func createOrder(c *gin.Context) {
	var req CreateOrder
	if err := c.ShouldBind(&req); err != nil {
		return
	}
	c.JSON(200, req)
}

func createMessage(c *gin.Context) {
	var msg Message
	if err := c.ShouldBindJSON(&msg); err != nil {
		return
	}
	c.JSON(200, msg)
}

func listItems(c *gin.Context) {
	var q paging
	if err := c.ShouldBindQuery(&q); err != nil {
		return
	}
}
