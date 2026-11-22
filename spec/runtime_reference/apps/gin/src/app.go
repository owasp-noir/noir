package reference

import (
	"example.org/reference/src/catalog"
	"github.com/gin-gonic/gin"
)

func Engine() *gin.Engine {
	engine := gin.New()
	engine.Use(catalog.Mark)
	api := engine.Group("/api")
	catalog.Register(api.Group("/catalog"))
	catalog.Register(engine.Group("/archive"))

	for _, path := range []string{"/recent", "/popular", "/featured"} {
		engine.GET(path, catalog.Reply)
	}
	const status = "/status"
	engine.GET(status+"/ready", catalog.Reply)
	engine.Any("/echo", catalog.Reply)
	return engine
}
