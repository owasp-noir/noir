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
