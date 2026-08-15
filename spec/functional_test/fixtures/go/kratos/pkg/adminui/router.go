// A sibling admin UI mounted with Gin instead of Kratos, living in the
// same module. Exists to prove the Kratos analyzer's import-marker gate
// keeps it from claiming a route registered by a different framework in
// the same repository (analyzer project scoping).
package adminui

import "github.com/gin-gonic/gin"

func NewRouter() *gin.Engine {
	r := gin.Default()
	r.GET("/admin/ping", func(c *gin.Context) {
		c.String(200, "pong")
	})
	return r
}
