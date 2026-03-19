package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

func apiRouter() http.Handler {
	r := chi.NewRouter()
	r.Get("/users", func(w http.ResponseWriter, r *http.Request) {
		page := r.URL.Query().Get("page")
		_ = page
	})
	r.Post("/users", func(w http.ResponseWriter, r *http.Request) {
		name := r.FormValue("name")
		_ = name
	})
	r.Route("/settings", func(r chi.Router) {
		r.Get("/", func(w http.ResponseWriter, r *http.Request) {
			token := r.Header.Get("Authorization")
			_ = token
		})
		r.Put("/", func(w http.ResponseWriter, r *http.Request) {
			theme := r.FormValue("theme")
			_ = theme
		})
	})
	return r
}
