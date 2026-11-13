package server

import (
	"github.com/gin-gonic/gin"

	"example.com/registrar/middleware"
	"example.com/registrar/router"
)

type UIConf struct {
	APIBaseURL string
}

func NewHTTPServer(uiConf *UIConf, apiRouter *router.APIRouter, pluginRouter *router.PluginRouter, authMw *middleware.AuthUserMiddleware) *gin.Engine {
	r := gin.New()

	// The route must be available without logging in
	mustUnAuthV1 := r.Group(uiConf.APIBaseURL + "/answer/api/v1")
	apiRouter.RegisterMustUnAuthAPIRouter(authMw, mustUnAuthV1)

	// No login needed by default: Auth() only reads the user, and
	// EjectUserBySiteInfo() refuses only when the site requires a login.
	unAuthV1 := r.Group(uiConf.APIBaseURL + "/answer/api/v1")
	unAuthV1.Use(authMw.Auth(), authMw.EjectUserBySiteInfo())
	apiRouter.RegisterUnAuthAPIRouter(unAuthV1)

	authV1 := r.Group(uiConf.APIBaseURL + "/answer/api/v1")
	authV1.Use(authMw.MustAuth())
	apiRouter.RegisterAPIRouter(authV1)

	adminV1 := r.Group(uiConf.APIBaseURL + "/answer/admin/api")
	adminV1.Use(authMw.AdminAuth())
	apiRouter.RegisterAdminAPIRouter(adminV1)

	// One registrar handed a public and a guarded group.
	pluginRouter.RegisterConnectorRouter(mustUnAuthV1)
	pluginRouter.RegisterConnectorRouter(authV1)

	// One registrar handed two guarded groups.
	pluginRouter.RegisterUserCenterRouter(authV1)
	pluginRouter.RegisterUserCenterRouter(adminV1)
	return r
}
