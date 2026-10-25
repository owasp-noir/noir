package server

import (
	"net/http"

	"example.com/app/api"
	"example.com/app/fever"
	"example.com/app/reader"
	"example.com/app/ui"
)

func newRouter() http.Handler {
	probe := newProbe()

	app := http.NewServeMux()
	app.HandleFunc("GET /healthcheck", probe)
	feverHandler := fever.Middleware()(fever.NewHandler())
	app.Handle("/fever/", feverHandler)
	readerHandler := reader.NewHandler()
	app.Handle("/reader/", readerHandler)
	app.Handle("/v1/", api.NewHandler())
	app.Handle("/", ui.Serve())

	var appHandler http.Handler = app
	appHandler = headers(appHandler)

	root := http.NewServeMux()
	root.HandleFunc("/liveness", liveness)
	root.Handle("/", appHandler)
	return root
}

func headers(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Frame-Options", "DENY")
		next.ServeHTTP(w, r)
	})
}
