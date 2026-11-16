package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

func main() {
	r := chi.NewRouter()
	r.Get("/healthz", health)
	r.Route("/api", func(r chi.Router) {
		r.Route("/v1", func(r chi.Router) {
			r.Get("/me", me)
			r.Mount("/admin", adminRouter())
		})
		r.Mount("/internal", internalRouter())
	})
	r.Mount("/debug", debugRouter())
	http.ListenAndServe(":3000", r)
}

func adminRouter() http.Handler {
	r := chi.NewRouter()
	r.Get("/users", adminListUsers)
	r.Delete("/users/{userID}", adminDeleteUser)
	r.Route("/jobs", func(r chi.Router) {
		r.Mount("/queue", queueRouter())
	})
	return r
}

func queueRouter() http.Handler {
	r := chi.NewRouter()
	r.Post("/flush", flushQueue)
	return r
}

func internalRouter() http.Handler {
	r := chi.NewRouter()
	r.Get("/metrics", metrics)
	return r
}

func debugRouter() http.Handler {
	r := chi.NewRouter()
	r.Get("/vars", vars)
	return r
}

func health(w http.ResponseWriter, r *http.Request)          {}
func me(w http.ResponseWriter, r *http.Request)              {}
func adminListUsers(w http.ResponseWriter, r *http.Request)  {}
func adminDeleteUser(w http.ResponseWriter, r *http.Request) {}
func flushQueue(w http.ResponseWriter, r *http.Request)      {}
func metrics(w http.ResponseWriter, r *http.Request)         {}
func vars(w http.ResponseWriter, r *http.Request)            {}
