package main

import (
	"net/http"

	"example.com/chires/posts"
	"example.com/chires/todos"
	"example.com/chires/users"
	"github.com/go-chi/chi/v5"
)

type localResource struct{}

func (rs localResource) Routes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", rs.List)
	return r
}

func (rs localResource) List(w http.ResponseWriter, r *http.Request) {}

type app struct {
	users *users.Resource
}

func main() {
	r := chi.NewRouter()
	a := &app{users: &users.Resource{}}

	r.Mount("/local", localResource{}.Routes())
	// The resource declared in its own package.
	r.Mount("/todos", todos.Resource{}.Routes())
	// Bound to a variable first.
	pr := &posts.Resource{}
	r.Mount("/posts", pr.Routes())
	var tr todos.Resource
	r.Mount("/todos-var", tr.Routes())
	// Held in a struct field.
	r.Mount("/users", a.users.Routes())

	// The closure parameter shadows `r`; the mount below is on the outer one.
	r.Route("/articles", func(r chi.Router) {
		r.Get("/", listArticles)
	})
	admin := chi.NewRouter()
	admin.Get("/accounts", listArticles)
	r.Mount("/admin", admin)

	_ = http.ListenAndServe(":3000", r)
}

func listArticles(w http.ResponseWriter, r *http.Request) {}
