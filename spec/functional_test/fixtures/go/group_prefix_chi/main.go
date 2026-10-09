package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

func main() {
	r := chi.NewRouter()
	r.Route("/users", userRoutes)
	http.ListenAndServe(":8080", r)
}

func userRoutes(r chi.Router) {
	r.Get("/", func(w http.ResponseWriter, req *http.Request) {})
	r.Get("/{id}", func(w http.ResponseWriter, req *http.Request) {})
}
