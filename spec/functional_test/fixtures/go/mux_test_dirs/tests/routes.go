package tests

import (
	"net/http"

	"github.com/gorilla/mux"
)

func NewRouter() *mux.Router {
	r := mux.NewRouter()
	r.HandleFunc("/from-tests", func(w http.ResponseWriter, r *http.Request) {}).Methods("GET")
	return r
}
