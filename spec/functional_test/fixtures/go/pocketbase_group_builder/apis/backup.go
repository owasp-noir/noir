package apis

import (
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
)

func H(e *core.RequestEvent) error { return nil }

// The group is the second argument, as in pocketbase's own bindBackupApi.
func BindBackupApi(app core.App, rg *router.RouterGroup[*core.RequestEvent]) {
	sub := rg.Group("/backups")
	sub.GET("", H).Bind(apis.RequireSuperuserAuth())
	sub.DELETE("/{key}", H).Bind(apis.RequireSuperuserAuth())
}

func BindFirst(rg *router.RouterGroup[*core.RequestEvent]) {
	rg.GET("/first", H)
}

func BindSQL(rg *router.RouterGroup[*core.RequestEvent]) {
	sg := rg.Group("/sql").Bind(apis.RequireSuperuserAuth())
	sg.POST("", H)
}
