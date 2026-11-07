package e2e

import (
	"net/http"

	"github.com/gorilla/mux"
)

func NewRouter() *mux.Router {
	r := mux.NewRouter()
	r.HandleFunc("/from-e2e", func(w http.ResponseWriter, r *http.Request) {}).Methods("GET")
	return r
}
