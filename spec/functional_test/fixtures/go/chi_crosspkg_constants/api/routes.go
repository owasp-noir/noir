package main

import (
	"net/http"

	"example.com/chi-crosspkg-constants/routepaths"
	"example.com/chi-crosspkg-constants/scim"
	"github.com/go-chi/chi/v5"
	external "github.com/third-party/routepaths"
)

func routes() http.Handler {
	r := chi.NewRouter()
	r.Route(scim.BasePath, func(r chi.Router) {
		r.Get("/ResourceTypes", handler)
	})
	r.Get(scim.BasePath+"/Schemas", handler)
	r.Route(scim.HelperPath, func(r chi.Router) {
		registerHelper(r)
	})
	r.Mount(scim.MountPath, mountedRoutes())

	r.Route(routepaths.VariablePrefix, func(r chi.Router) {
		r.Get("/variable", handler)
	})
	r.Get(routepaths.FunctionPrefix()+"/function", handler)
	r.Get(routepaths.PathType("/typed"), handler)
	r.Get(external.BasePath+"/third-party", handler)
	return r
}

func registerHelper(r chi.Router) {
	r.Get("/helper", handler)
}

func mountedRoutes() http.Handler {
	r := chi.NewRouter()
	r.Get(scim.MountedEndpointPath, handler)
	return r
}

func handler(http.ResponseWriter, *http.Request) {}
