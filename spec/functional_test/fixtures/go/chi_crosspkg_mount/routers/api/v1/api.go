package v1

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

// Routes builds the API router that main mounts at "/api/v1".
func Routes() http.Handler {
	r := chi.NewRouter()
	r.Get("/users", func(w http.ResponseWriter, r *http.Request) {
		page := r.URL.Query().Get("page")
		_ = page
	})
	r.Route("/repos", func(r chi.Router) {
		r.Get("/{owner}/{repo}", func(w http.ResponseWriter, r *http.Request) {
			owner := chi.URLParam(r, "owner")
			_ = owner
		})
		r.Post("/{owner}/{repo}/issues", func(w http.ResponseWriter, r *http.Request) {
			title := r.FormValue("title")
			_ = title
		})
	})
	// A nested mount inside a mounted router composes both prefixes.
	r.Mount("/admin", adminRouter())
	return r
}
