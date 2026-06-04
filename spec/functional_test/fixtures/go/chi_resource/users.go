package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

type usersResource struct{}

func (rs usersResource) Routes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", rs.List)
	r.Route("/{id}", func(r chi.Router) {
		r.Put("/", rs.Update)
	})
	return r
}

func (rs usersResource) List(w http.ResponseWriter, r *http.Request)   {}
func (rs usersResource) Update(w http.ResponseWriter, r *http.Request) {}
