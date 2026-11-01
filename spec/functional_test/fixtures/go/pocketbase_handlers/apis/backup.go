package apis

import "github.com/pocketbase/pocketbase/core"

// Declared in another file of the package than its route.
func backupDownload(e *core.RequestEvent) error {
	fileToken := e.Request.URL.Query().Get("token")
	if e.Request.Header.Get("X-Backup-Key") == "" {
		return e.ForbiddenError("missing key", nil)
	}
	_ = fileToken
	return nil
}
