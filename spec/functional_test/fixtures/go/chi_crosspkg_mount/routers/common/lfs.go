package common

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

// AddLFSRoutes is shared by several routers.
func AddLFSRoutes(r chi.Router) {
	r.Post("/info/lfs/objects/batch", BatchHandler)
}

func BatchHandler(w http.ResponseWriter, r *http.Request) {}
