package routes

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

func addUserRoutes(rg *gin.RouterGroup) {
	users := rg.Group("/users")

	users.GET("/", func(c *gin.Context) { c.JSON(http.StatusOK, "users") })
	users.GET("/comments", func(c *gin.Context) { c.JSON(http.StatusOK, "comments") })
	users.POST("/", func(c *gin.Context) { c.JSON(http.StatusOK, "create") })
}
