package routes

import "github.com/gin-gonic/gin"

var router = gin.Default()

// getRoutes splits registration across per-resource helpers, each
// receiving a versioned group. addPingRoutes is reused under /v1 and /v2.
func getRoutes() {
	v1 := router.Group("/v1")
	addUserRoutes(v1)
	addPingRoutes(v1)

	v2 := router.Group("/v2")
	addPingRoutes(v2)
}
