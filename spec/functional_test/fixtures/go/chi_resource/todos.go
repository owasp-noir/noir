package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

type todosResource struct{}

func (rs todosResource) Routes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", rs.List)
	r.Post("/", rs.Create)
	r.Route("/{id}", func(r chi.Router) {
		r.Get("/", rs.Get)
		r.Delete("/", rs.Delete)
	})
	return r
}

func (rs todosResource) List(w http.ResponseWriter, r *http.Request)   {}
func (rs todosResource) Create(w http.ResponseWriter, r *http.Request) {}
func (rs todosResource) Get(w http.ResponseWriter, r *http.Request)    {}
func (rs todosResource) Delete(w http.ResponseWriter, r *http.Request) {}
