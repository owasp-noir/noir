package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

// No go.mod of its own: part of example.com/lib, so `_examples` excludes it.
func main() {
	r := chi.NewRouter()
	r.Get("/skipped", func(w http.ResponseWriter, r *http.Request) {})
	http.ListenAndServe(":3001", r)
}
