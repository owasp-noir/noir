package main

import (
	"net/http"

	"github.com/gorilla/mux"
)

var r *mux.Router

func main() {
	root := mux.NewRouter()
	r = root.PathPrefix("/api").Subrouter()
	setup()
	http.ListenAndServe(":8080", root)
}
