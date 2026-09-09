package web

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

// Routes builds the web router that main mounts at "/".
func Routes() http.Handler {
	r := chi.NewRouter()
	r.Get("/metrics", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("metrics"))
	})
	return r
}
