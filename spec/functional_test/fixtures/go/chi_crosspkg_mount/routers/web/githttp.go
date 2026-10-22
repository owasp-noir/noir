package web

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

func addGitRoutes(r chi.Router) {
	r.Get("/info/refs", getInfoRefs)
	r.Post("/git-upload-pack", serviceUploadPack)
}

func getInfoRefs(w http.ResponseWriter, r *http.Request) {}

func serviceUploadPack(w http.ResponseWriter, r *http.Request) {}
