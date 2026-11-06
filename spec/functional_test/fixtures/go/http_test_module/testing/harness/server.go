package harness

import "net/http"

// A module named `testing` is not a test tree by name alone.
func Routes(mux *http.ServeMux) {
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {})
}
