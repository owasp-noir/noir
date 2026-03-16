package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

func apiRouter() http.Handler {
	r := chi.NewRouter()
	r.Get("/users", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("users list"))
	})
	r.Post("/users", func(w http.ResponseWriter, r *http.Request) {
		name := r.FormValue("name")
		_ = name
	})
	r.Route("/settings", func(r chi.Router) {
		r.Get("/", func(w http.ResponseWriter, r *http.Request) {
			w.Write([]byte("settings"))
		})
		r.Put("/", func(w http.ResponseWriter, r *http.Request) {
			w.Write([]byte("update settings"))
		})
	})
	return r
}
