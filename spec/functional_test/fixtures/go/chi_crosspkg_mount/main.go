package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	apiv1 "example.com/crosspkg/routers/api/v1"
	"example.com/crosspkg/routers/web"
)

func main() {
	r := chi.NewRouter()

	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok"))
	})

	// Sub-routers built in other packages: the mount prefix must land on
	// every route they register, and the root mount must not double the
	// slash.
	r.Mount("/", web.Routes())
	r.Mount("/api/v1", apiv1.Routes())

	http.ListenAndServe(":3000", r)
}
