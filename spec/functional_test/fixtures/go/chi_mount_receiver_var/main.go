package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"example.com/blog/tags"
)

type commentsResource struct{}

func (rs *commentsResource) Routes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", listComments)
	return r
}

func main() {
	r := chi.NewRouter()
	r.Get("/", index)

	h := tags.NewHandler()
	r.Mount("/tags", h.Routes())

	comments := &commentsResource{}
	r.Mount("/comments", comments.Routes())

	http.ListenAndServe(":3000", r)
}

func index(w http.ResponseWriter, r *http.Request)        {}
func listComments(w http.ResponseWriter, r *http.Request) {}
