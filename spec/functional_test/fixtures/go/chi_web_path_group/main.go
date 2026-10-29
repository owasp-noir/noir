package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"example.com/giteaish/modules/web"
)

var _ = chi.NewRouter

func h(w http.ResponseWriter, r *http.Request) {}

func routes() *web.Router {
	m := web.NewRouter()
	m.Group("/pulls", func() {
		m.Group("/{index}", func() {
			m.Get("", h)
			m.Get(".{diffType:diff|patch}", h)
		})
	})
	m.Get("/feed.rss", h)
	m.Group("/commits", func() {
		m.PathGroup("/*", func(g *web.RouterPathGroup) {
			g.MatchPath("GET", "/<ref:*>/status", h)
			g.MatchPath("POST, PUT", "/<ref:*>/upload/<name>", h)
		})
	})
	return m
}

func main() {
	http.ListenAndServe(":8080", routes())
}
