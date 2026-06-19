// PocketBase route files can receive a router group from a hook/event
// without importing pocketbase/tools/router in that file. The analyzer
// should still scan the package once another file identifies the package
// as PocketBase-backed.
package main

func bindNoImportRoutes(rg RouterGroup) {
	uiGroup := rg.Group("/_")
	uiGroup.GET("/extensions.js", listFoos)
}

type RouterGroup interface {
	Group(string) RouterGroup
	GET(string, any)
}
