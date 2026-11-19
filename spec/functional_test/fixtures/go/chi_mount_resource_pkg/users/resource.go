package users

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

type Resource struct{}

func (rs *Resource) Routes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", rs.List)
	r.Get("/{id}", rs.Get)
	return r
}

func (rs *Resource) List(w http.ResponseWriter, r *http.Request) {}
func (rs *Resource) Get(w http.ResponseWriter, r *http.Request)  {}
