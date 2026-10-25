package server

import (
	"net/http"

	"example.com/app/api"
	"example.com/app/fever"
)

func newRouter() http.Handler {
	probe := newProbe()

	app := http.NewServeMux()
	app.HandleFunc("GET /healthcheck", probe)
	feverHandler := fever.Middleware()(fever.NewHandler())
	app.Handle("/fever/", feverHandler)
	app.Handle("/v1/", api.NewHandler())

	root := http.NewServeMux()
	root.HandleFunc("/liveness", liveness)
	root.Handle("/", app)
	return root
}
