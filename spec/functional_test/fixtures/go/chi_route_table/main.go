package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

func main() {
	r := chi.NewRouter()
	routes := []struct {
		method  string
		path    string
		handler http.HandlerFunc
	}{
		{http.MethodGet, "/users", listUsers},
		{http.MethodPost, "/users", createUser},
		{method: http.MethodDelete, path: "/users/{id}", handler: deleteUser},
	}
	for _, rt := range routes {
		r.MethodFunc(rt.method, rt.path, rt.handler)
	}

	// Not a route table: a client call with no handler.
	links := []struct{ url string }{{"/external"}}
	for _, l := range links {
		_, _ = http.Get(l.url)
	}
	_ = http.ListenAndServe(":8080", r)
}

func listUsers(w http.ResponseWriter, r *http.Request) {
	_ = r.URL.Query().Get("page")
}
func createUser(w http.ResponseWriter, r *http.Request) {}
func deleteUser(w http.ResponseWriter, r *http.Request) {}
