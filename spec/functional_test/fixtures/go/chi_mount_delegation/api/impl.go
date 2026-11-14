package api

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

type Impl struct{}

func (Impl) GetStatus(w http.ResponseWriter, r *http.Request)  {}
func (Impl) ListItems(w http.ResponseWriter, r *http.Request)  {}
func (Impl) CreateItem(w http.ResponseWriter, r *http.Request) {}

// Delegates the same way Handler does, but nothing mounts it.
func Unmounted() http.Handler {
	return healthRouter()
}

func healthRouter() http.Handler {
	r := chi.NewRouter()
	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {})
	return r
}
