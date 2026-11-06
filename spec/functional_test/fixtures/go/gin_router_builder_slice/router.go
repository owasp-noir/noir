package router

import "github.com/gin-gonic/gin"

var (
	routerNoCheckRole = make([]func(*gin.RouterGroup), 0)
	routerCheckRole   = make([]func(v1 *gin.RouterGroup, auth gin.HandlerFunc), 0)
)

// Each module appends its builder in init(); the routes are served under
// the group the loop hands every builder.
func InitRouter(r *gin.Engine, auth gin.HandlerFunc) {
	v := r.Group("/api/v1")
	for _, f := range routerNoCheckRole {
		f(v)
	}
	authed := r.Group("/api/v1")
	for _, f := range routerCheckRole {
		f(authed, auth)
	}
}
