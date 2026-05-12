package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

func main() {
	r := chi.NewRouter()
	r.Post("/users", createUser)
	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok"))
	})
	r.Route("/profile", func(r chi.Router) {
		r.Get("/", listProfile)
	})
	http.ListenAndServe(":8080", r)
}
