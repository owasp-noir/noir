package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

func listProjects(w http.ResponseWriter, r *http.Request)  {}
func getProject(w http.ResponseWriter, r *http.Request)    {}
func deleteProject(w http.ResponseWriter, r *http.Request) {}
func listSecrets(w http.ResponseWriter, r *http.Request)   {}
func home(w http.ResponseWriter, r *http.Request)          {}
func orphan(w http.ResponseWriter, r *http.Request)        {}

// addProjectRoutes registers one scope's project tree on the router it
// is handed. It is called from two groups, so its routes exist under
// both prefixes — and under neither on their own.
func addProjectRoutes(r chi.Router) {
	r.Get("/projects", listProjects)
	r.Route("/projects/{id}", func(r chi.Router) {
		r.Get("/", getProject)
		r.Delete("/", deleteProject)
	})
}

// neverCalled takes a router too, but nothing calls it: its routes keep
// their prefix-less path exactly as before.
func neverCalled(r chi.Router) {
	r.Get("/orphan", orphan)
}

func main() {
	r := chi.NewRouter()
	r.Get("/", home)

	// A closure helper bound to a variable is expanded the same way.
	addSecretRoutes := func(m chi.Router) {
		m.Get("/secrets", listSecrets)
	}

	r.Route("/orgs/{org}", func(r chi.Router) {
		addProjectRoutes(r)
		addSecretRoutes(r)
	})
	r.Route("/repos/{owner}/{repo}", func(r chi.Router) {
		addProjectRoutes(r)
	})

	http.ListenAndServe(":3000", r)
}
