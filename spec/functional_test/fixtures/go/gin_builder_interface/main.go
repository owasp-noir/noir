package main

import "github.com/gin-gonic/gin"

func main() {
	r := gin.Default()
	v1 := r.Group("/api/v1")

	registerUsers(v1.Group("/users"))
	// gin.IRouter: what both *gin.Engine and *gin.RouterGroup satisfy.
	registerOrders(v1.Group("/orders"))
	registerHealth(v1)
	// Handed the engine as well as a group: read once, as written.
	registerShared(r)
	registerShared(v1)

	_ = r.Run()
}

func registerUsers(rg *gin.RouterGroup) {
	rg.GET("", h)
}

func registerOrders(rg gin.IRouter) {
	rg.GET("", h)
	rg.GET("/:id", h)
	items := rg.Group("/:id/items")
	items.POST("", h)
}

func registerHealth(rg gin.IRoutes) {
	rg.GET("/healthz", h)
}

func registerShared(rg gin.IRouter) {
	rg.GET("/shared", h)
}

func h(c *gin.Context) {}
