package user

import "github.com/gin-gonic/gin"

func RegisterRoutes(rg *gin.RouterGroup) {
	rg.GET("", list)
	rg.POST("", create)
	rg.GET("/:id", get)
}

func list(c *gin.Context)   {}
func create(c *gin.Context) {}
func get(c *gin.Context)    {}
