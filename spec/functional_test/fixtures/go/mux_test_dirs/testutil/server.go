package testutil

import (
	"net/http"

	"github.com/gorilla/mux"
)

// "testutil" is not the test/ segment. A helper package with this name
// can still be production code, so its routes stay.
func NewRouter() *mux.Router {
	r := mux.NewRouter()
	r.HandleFunc("/kept", func(w http.ResponseWriter, r *http.Request) {}).Methods("GET")
	return r
}
