package integration

import (
	"net/http"

	"github.com/gorilla/mux"
)

func NewRouter() *mux.Router {
	r := mux.NewRouter()
	r.HandleFunc("/from-integration", func(w http.ResponseWriter, r *http.Request) {}).Methods("GET")
	return r
}
