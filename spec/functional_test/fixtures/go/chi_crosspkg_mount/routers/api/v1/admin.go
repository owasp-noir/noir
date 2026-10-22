package v1

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

func adminRouter() http.Handler {
	r := chi.NewRouter()
	r.Delete("/users/{id}", func(w http.ResponseWriter, r *http.Request) {
		id := chi.URLParam(r, "id")
		_ = id
	})
	return r
}
