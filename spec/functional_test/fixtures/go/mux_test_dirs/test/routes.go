package test

import (
	"net/http"

	"github.com/gorilla/mux"
)

// Directly under test/. Dropped when the scan base is the repo, kept
// when the scan base is this directory.
func NewRouter() *mux.Router {
	r := mux.NewRouter()
	r.HandleFunc("/from-test", func(w http.ResponseWriter, r *http.Request) {}).Methods("GET")
	return r
}
