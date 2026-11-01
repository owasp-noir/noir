package apis

import (
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
)

type fileApi struct{}

func BindFileApi(app core.App, rg *router.RouterGroup[*core.RequestEvent]) {
	api := fileApi{}
	sub := rg.Group("/files")
	sub.GET("/{collection}/{recordId}/{filename}", api.download)
	sub.GET("/{key}", backupDownload)
	sub.POST("/token", api.fileToken)
}

func (api *fileApi) download(e *core.RequestEvent) error {
	token := e.Request.URL.Query().Get("token")
	thumb := e.Request.URL.Query().Get("thumb")
	_, _ = token, thumb
	return nil
}

func (api *fileApi) fileToken(e *core.RequestEvent) error {
	return e.JSON(200, map[string]string{"token": "x"})
}

// helperReadsQuery is no handler: its read belongs to nobody.
func helperReadsQuery(e *core.RequestEvent) string {
	return e.Request.URL.Query().Get("unrelated")
}
