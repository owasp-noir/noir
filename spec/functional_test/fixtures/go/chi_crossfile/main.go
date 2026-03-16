package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

func main() {
	r := chi.NewRouter()

	r.Get("/", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("home"))
	})

	// Mount router defined in another file
	r.Mount("/api", apiRouter())

	http.ListenAndServe(":3333", r)
}
