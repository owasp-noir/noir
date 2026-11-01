package server

import (
	"net/http"

	"example.com/app/internal/httphandler"
	"example.com/app/server/api"
	"example.com/app/server/fileserver"
)

func New() http.Handler {
	mux := http.NewServeMux()
	mux.Handle("/healthz", httphandler.GET(httphandler.Func(func(w http.ResponseWriter, r *http.Request) error {
		return nil
	}), nil))
	(&fileserver.Service{}).RegisterRoutes(mux, nil)

	// The API mux is served under /api.
	apiMux := http.NewServeMux()
	api.Register(apiMux)
	mux.Handle("/api/", http.StripPrefix("/api", apiMux))

	// A mux mounted under a pattern this file cannot resolve.
	pluginMux := http.NewServeMux()
	api.RegisterPlugins(pluginMux)
	mux.Handle(pluginPrefix(), http.StripPrefix(pluginPrefix(), pluginMux))
	return mux
}

func pluginPrefix() string { return "/plugins/" }
