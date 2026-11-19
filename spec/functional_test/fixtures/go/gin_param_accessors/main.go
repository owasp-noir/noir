package main

import "github.com/gin-gonic/gin"

func main() {
	r := gin.Default()

	// control: the accessors gin.cr reads today
	r.GET("/a00-control", func(c *gin.Context) {
		_ = c.Query("ok_query")
		_ = c.DefaultQuery("ok_default", "x")
		_ = c.GetHeader("X-Ok")
	})
	// gin docs "Map as querystring or postform parameters" / "Bind html checkboxes"
	r.GET("/a01-query-collections", func(c *gin.Context) {
		_ = c.QueryArray("ids")
		_ = c.QueryMap("filter")
		_, _ = c.GetQueryArray("tags")
	})
	r.POST("/a02-form-collections", func(c *gin.Context) {
		_ = c.PostFormArray("colors")
		_ = c.PostFormMap("names")
	})
	// gin docs "Upload files"
	r.POST("/a03-upload", func(c *gin.Context) {
		_, _ = c.FormFile("avatar")
	})
	// two reads on one line
	r.GET("/a04-two-on-a-line", func(c *gin.Context) {
		page, size := c.Query("page"), c.Query("size")
		_, _ = page, size
	})
	// the stdlib request behind the context
	r.GET("/a05-stdlib-request", func(c *gin.Context) {
		_ = c.Request.URL.Query().Get("raw_q")
		_ = c.Request.FormValue("raw_form")
		_ = c.Request.PostFormValue("raw_post")
	})
	_ = r.Run()
}
