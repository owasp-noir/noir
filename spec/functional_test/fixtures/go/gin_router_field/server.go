package main

import (
	"net/http"

	g "github.com/gin-gonic/gin"
	"github.com/spf13/viper"
)

type cache interface {
	Get(key string, def string) string
}

type store interface {
	Delete(path string, id string) error
}

type Server struct {
	router *g.Engine
	Router *g.Engine
	engine *g.Engine
	api    *g.RouterGroup
	admin  g.IRouter
	client *http.Client
	cache  cache
	db     store
}

func (s *Server) routes() {
	s.router.GET("/lower", s.h)
	s.Router.GET("/upper", s.h)
	s.engine.POST("/engine", s.h)

	api := s.router.Group("/api")
	api.GET("/x", s.h)

	s.api = s.router.Group("/v1")
	s.admin = s.engine.Group("/admin")
	s.router.Group("/chain").GET("/z", s.h)
}

func (s *Server) more() {
	s.api.GET("/y", s.items)
	s.admin.DELETE("/users/:id", s.h)
}

func (s *Server) lookups(c *g.Context, r *http.Request) {
	// None of these are routes.
	c.Request.Get("/not-a-route", s.h)
	r.Header.Get("/not-a-route-header")
	c.Request.URL.Query().Get("/not-a-route-query")
	s.client.Get("/not-a-route-client")
	s.cache.Get("/not-a-route-cache", "fallback")
	s.db.Delete("/not-a-route-db", "id")
	viper.Get("/not-a-route-viper")
}

func (s *Server) h(c *g.Context) {}

func (s *Server) items(c *g.Context) {
	_ = c.Query("page")
}

func main() {
	e := g.New()
	s := &Server{router: e, Router: e, engine: e}
	s.routes()
	s.more()
	e.GET("/direct", s.items)
	e.Run()
}
