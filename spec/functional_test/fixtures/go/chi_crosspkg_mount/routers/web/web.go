package web

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"example.com/crosspkg/routers/common"
)

// Routes builds the web router that main mounts at "/".
func Routes() http.Handler {
	r := chi.NewRouter()
	r.Get("/metrics", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("metrics"))
	})
	// Route helpers declared in a sibling file and in another package
	// register under the prefix active at their call site.
	r.Route("/{owner}/{repo}", func(r chi.Router) {
		addGitRoutes(r)
		common.AddLFSRoutes(r)
	})
	return r
}
