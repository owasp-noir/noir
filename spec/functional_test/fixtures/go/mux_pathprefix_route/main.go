package main

import (
	"net/http"
	"net/http/httputil"

	"github.com/gorilla/mux"
)

func main() {
	r := mux.NewRouter()

	r.HandleFunc("/health", health).Methods("GET")

	// Everything under the prefix reaches the handler.
	r.PathPrefix("/proxy/").Handler(&httputil.ReverseProxy{})
	r.PathPrefix("/webhooks/").HandlerFunc(webhook).Methods("POST")

	// A file server is a static mount, not a route.
	r.PathPrefix("/assets/").Handler(http.StripPrefix("/assets/", http.FileServer(http.Dir("./assets/"))))

	// The subrouter's method matcher scopes its routes.
	ro := r.PathPrefix("/readonly").Methods("GET", "HEAD").Subrouter()
	ro.HandleFunc("/items", health)
	ro.HandleFunc("/purge", health).Methods("POST")

	// A subrouter used inline.
	r.PathPrefix("/inline").Subrouter().HandleFunc("/ping", health).Methods("GET")

	_ = http.ListenAndServe(":8080", r)
}

func health(w http.ResponseWriter, r *http.Request)  {}
func webhook(w http.ResponseWriter, r *http.Request) { _ = r.Header.Get("X-Signature") }
