package v1

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"example.com/crosspkg/routers/api/v1/repo"
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
		// Handlers declared in an imported package; the regex constraint
		// is what tells the two routes apart, and `*` takes the rest.
		r.Get("/{owner}/{repo}/{type:issues}/{index}", repo.GetIssue)
		r.Get("/{owner}/{repo}/{type:pulls}/{index}", repo.GetPull)
		r.Get("/{owner}/{repo}/contents/*", repo.GetContents)
	})
	// A nested mount inside a mounted router composes both prefixes.
	r.Mount("/admin", adminRouter())
	return r
}
