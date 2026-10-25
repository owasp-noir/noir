package router

import (
	"github.com/gin-gonic/gin"
	"github.com/test/gin-struct-handlers/api"
	"github.com/test/gin-struct-handlers/auth"
)

func Create() *gin.Engine {
	g := gin.New()
	authentication := auth.Auth{}
	itemHandler := api.ItemAPI{}

	g.Match([]string{"GET", "HEAD"}, "/health", itemHandler.Health)
	g.GET("/page", serveFile("index.html"))
	g.Group("/").Use(authentication.RequireUser).POST("/message", itemHandler.CreateMessage)
	g.GET("/public", itemHandler.Public)
	g.Group("/signup").Use(authentication.OptionalUser).POST("", itemHandler.Signup)

	g.POST("/login", itemHandler.Login)

	private := g.Group("")
	{
		private.Use(authentication.RequireUser)
		items := private.Group("/items")
		{
			items.GET("", itemHandler.ListItems)
			items.PUT("/:id", itemHandler.UpdateItem)
		}
		client := private.Group("/client")
		client.GET("/:id", itemHandler.GetClient)
	}
	return g
}

func serveFile(name string) gin.HandlerFunc {
	content := "<html>" + name
	return func(c *gin.Context) {
		c.String(200, content)
	}
}
