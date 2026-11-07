// `integration` is a production package name (internal/integration/...),
// not a test tree. Routes here are part of the API.
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
