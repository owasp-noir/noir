package main

import (
	"regexp"
	"sync"

	"github.com/gin-gonic/gin"
	"golang.org/x/sync/errgroup"
	"golang.org/x/sync/singleflight"
)

type Config struct{ Base string }

type database struct{}

func (database) Group(string) database { return database{} }
func (database) GET(string, any)       {}

func register(g *gin.RouterGroup) {
	g.GET("/users", list)
}

func list(c *gin.Context)   {}
func ping(c *gin.Context)   {}
func status(c *gin.Context) {}
func runtimeTail() string   { return "" }

func main() {
	cfg := Config{Base: "/svc"}
	r := gin.New()
	suffix := runtimeTail()

	r.Group("/v0").GET("/ping", ping)
	r.Group(cfg.Base + "/v1").GET("/status", status)
	r.Group(cfg.Base).GET("/root", status)
	r.Group(cfg.Base+"/v1").Group("/admin").GET("/users", list)
	r.Group(cfg.Base+"/v1"+suffix).GET("/gap", status)

	register(r.Group(cfg.Base + "/v2"))
	register(r.Group(cfg.Base))

	lookalikes(cfg)
	r.Run()
}

func lookalikes(cfg Config) {
	var errgroupGroup errgroup.Group
	_ = errgroupGroup
	var wait sync.WaitGroup
	wait.Add(1)
	wait.Done()
	_ = regexp.MustCompile(`(user)/(\d+)`).FindAllStringSubmatch("user/1", -1)
	var flight singleflight.Group
	_ = flight
	var db database
	_ = db.Group("column")
	_ = db.Group(cfg.Base + "/column")
	db.Group(cfg.Base + "/column").GET("/not-a-route", status)
}
