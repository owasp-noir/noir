package e2e

import (
	"net/http"

	"github.com/gorilla/mux"
)

// Bench helpers — not part of the product API.
// Shopify/toxiproxy test/e2e/endpoint.go is this shape: not *_test.go.
func NewBenchRouter() *mux.Router {
	r := mux.NewRouter()
	r.HandleFunc("/test1", func(w http.ResponseWriter, r *http.Request) {})
	r.HandleFunc("/test2", func(w http.ResponseWriter, r *http.Request) {})
	return r
}
