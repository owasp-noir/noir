package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

func main() {
	r := chi.NewRouter()

	// OPTIONS method - not supported by chi analyzer (only GET/POST/PUT/DELETE/PATCH)
	r.Options("/cors", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})

	// HEAD method - not supported by chi analyzer
	r.Head("/ping", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	http.ListenAndServe(":3333", r)
}
