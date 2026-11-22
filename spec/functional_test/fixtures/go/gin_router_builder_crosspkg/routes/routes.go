package routes

import "github.com/gin-gonic/gin"

func RegisterUsers(rg *gin.RouterGroup) {
	users := rg.Group("/users")
	users.GET("/:id", func(c *gin.Context) {})
	users.POST("", func(c *gin.Context) {})
}

func RegisterPosts(rg *gin.RouterGroup) {
	rg.GET("/:slug", func(c *gin.Context) {})
}

type calendar struct {
	channel *gin.RouterGroup
}

func RegisterEvents(parent *gin.RouterGroup) {
	c := calendar{channel: parent.Group("/calendar")}
	c.register()
}

func (c calendar) register() {
	for _, entry := range []struct{ method, path string }{
		{"GET", "/events"},
		{"POST", "/events"},
	} {
		c.channel.Handle(entry.method, entry.path, func(ctx *gin.Context) {})
	}
}

// A different method on the same receiver only serves the preview branch.
func Preview(parent *gin.RouterGroup) {
	c := calendar{channel: parent.Group("/draft")}
	c.preview()
}

func (c calendar) preview() {
	c.channel.GET("/today", func(ctx *gin.Context) {})
}
