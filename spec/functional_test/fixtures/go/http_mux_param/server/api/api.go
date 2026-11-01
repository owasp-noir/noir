package api

import "net/http"

func Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /users", listUsers)
}

func RegisterPlugins(mux *http.ServeMux) {
	mux.HandleFunc("GET /hooks", listUsers)
}

func listUsers(w http.ResponseWriter, r *http.Request) {}
