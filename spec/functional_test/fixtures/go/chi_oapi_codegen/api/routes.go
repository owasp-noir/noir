package api

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

const apiPrefix = "/v1"

// Hand-written routes in the same shape: a local copy of the base, no
// Group wrapper, a package constant that resolves in full, and a runtime
// value between two literals, which is not a known path.
func Extra(r chi.Router, options ChiServerOptions, id string) {
	base := options.BaseURL
	r.Get(base+"/health", health)
	r.Delete(options.BaseURL+"/items/{itemId}", health)
	r.Get(apiPrefix+"/version", health)
	r.Get("/users/"+id+"/avatar", health)
	r.Get(options.BaseURL+id, health)
}

func health(w http.ResponseWriter, r *http.Request) {}
