package router

import "github.com/gin-gonic/gin"

func init() {
	routerCheckRole = append(routerCheckRole, registerProductRouter)
	routerNoCheckRole = append(routerNoCheckRole, registerPublicRouter)
}

func registerProductRouter(v1 *gin.RouterGroup, auth gin.HandlerFunc) {
	r := v1.Group("/product").Use(auth)
	{
		r.GET("", listProducts)
		r.POST("", createProduct)
	}
}

func registerPublicRouter(g *gin.RouterGroup) {
	g.GET("/captcha", captcha)
}

// Never appended, never called: keeps its own, prefix-less, route.
func registerOrphanRouter(g *gin.RouterGroup) {
	g.GET("/orphan", orphan)
}
