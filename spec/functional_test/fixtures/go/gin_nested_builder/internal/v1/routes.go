package v1

import (
	"example.com/nestedbuilder/internal/user"
	"github.com/gin-gonic/gin"
)

func Register(rg *gin.RouterGroup) {
	rg.GET("/ping", ping)

	// A group built off the parameter, bound to a local, handed on.
	orders := rg.Group("/orders")
	registerOrders(orders)

	// A group built off the parameter inline, handed to another package.
	user.RegisterRoutes(rg.Group("/users"))

	// The parameter itself handed on.
	registerMisc(rg)
}

func registerOrders(rg *gin.RouterGroup) {
	rg.GET("", ping)
	rg.GET("/:id", ping)
}

func registerMisc(rg *gin.RouterGroup) {
	rg.GET("/misc", ping)
}

func ping(c *gin.Context) {}
