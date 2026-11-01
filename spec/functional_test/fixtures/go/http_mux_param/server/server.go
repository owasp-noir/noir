package server

import (
	"net/http"

	"example.com/app/internal/hh"
	"example.com/app/server/fileserver"
)

func New() http.Handler {
	mux := http.NewServeMux()
	mux.Handle("/healthz", hh.GET(hh.Func(func(w http.ResponseWriter, r *http.Request) error {
		return nil
	}), nil))
	(&fileserver.Service{}).RegisterRoutes(mux, nil)
	return mux
}
