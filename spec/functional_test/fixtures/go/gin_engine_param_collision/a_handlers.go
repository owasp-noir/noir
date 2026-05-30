package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// registerSysJobRouter reuses the name `r` as a *local* group variable.
// In the engine entrypoint (z_router.go) `r` is the *gin.Engine root.
// The two must not be conflated across files, or `r`'s "/sysjob" prefix
// leaks onto `v1 := r.Group("/api/v1")` and pollutes every route.
func registerSysJobRouter(v1 *gin.RouterGroup) {
	r := v1.Group("/sysjob")
	r.GET("/list", func(c *gin.Context) { c.JSON(http.StatusOK, nil) })
	r.POST("/create", func(c *gin.Context) { c.JSON(http.StatusOK, nil) })

	v1.GET("/job/start", func(c *gin.Context) { c.JSON(http.StatusOK, nil) })
}
