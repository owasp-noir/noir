// `ShouldBind` follows the struct tags. Form-only tags are form params
// named by the tag; json is emitted when a `json` tag is present, or when
// the field is untagged (the exported name). `ShouldBindJSON` and
// `ShouldBindQuery` are unchanged.
package main

import (
	args "example.com/gin-shouldbind-form/input"
	"github.com/gin-gonic/gin"
)

type inputOptions = args.Options

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
	r.POST("/wrapped", func(c *gin.Context) {
		req := new(inputOptions)
		destination := req
		_ = args.Read(c, destination)
		_ = c.Query("dry_run")
	})
	r.GET("/combined/:id", func(c *gin.Context) {
		var in struct {
			ID    string `uri:"id" form:"-"`
			Limit int    `form:"limit" uri:"-"`
		}
		_ = c.ShouldBindQuery(&in)
		_ = c.Query("limit")
		_ = c.ShouldBindUri(&in)
		var h struct {
			Trace string `header:"X-Trace"`
		}
		_ = c.ShouldBindHeader(&h)
	})
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
