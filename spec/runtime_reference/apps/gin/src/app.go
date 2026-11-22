package reference

import (
	"os"

	"example.org/reference/src/catalog"
	"example.org/reference/src/circulation/desk"
	"github.com/gin-gonic/gin"
)

func Engine() *gin.Engine {
	engine := gin.New()
	engine.Use(catalog.Mark)
	api := engine.Group("/api")
	catalog.Register(api.Group("/catalog"))
	catalog.Register(engine.Group("/archive"))

	const memberBase = "/members"
	desk.Register(engine.Group(memberBase))
	staffBase := os.Getenv("STAFF_MOUNT")
	if staffBase == "" {
		staffBase = "/staff"
	}
	staff := engine.Group(staffBase)
	desk.Register(staff)
	staff.Any("/terminal/sync", desk.Accept)
	staff.Handle("HEAD", "/terminal/status", desk.Status)
	staff.GET("/terminal/status", desk.Status)

	for _, path := range []string{"/recent", "/popular", "/featured"} {
		engine.GET(path, catalog.Reply)
	}
	const status = "/status"
	engine.GET(status+"/ready", catalog.Reply)
	engine.Any("/echo", catalog.Reply)
	return engine
}
