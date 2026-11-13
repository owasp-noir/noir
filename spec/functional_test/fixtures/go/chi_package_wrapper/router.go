package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

// router wraps chi so handlers can return an error. The routes are
// registered from routes.go, which never imports chi.
type router struct {
	chi chi.Router
}

type apiHandler func(w http.ResponseWriter, r *http.Request) error

func newRouter() *router {
	return &router{chi.NewRouter()}
}

func (r *router) Route(pattern string, fn func(*router)) {
	r.chi.Route(pattern, func(c chi.Router) {
		fn(&router{c})
	})
}

func (r *router) With(mw func(http.Handler) http.Handler) *router {
	return &router{r.chi.With(mw)}
}

func (r *router) Get(pattern string, fn apiHandler) {
	r.chi.Get(pattern, handler(fn))
}

func (r *router) Post(pattern string, fn apiHandler) {
	r.chi.Post(pattern, handler(fn))
}

func (r *router) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	r.chi.ServeHTTP(w, req)
}

func handler(fn apiHandler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := fn(w, r); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
		}
	}
}
