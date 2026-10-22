// A Go sibling in the same tree: the Django pass must not claim its
// routes, and widening the Django pass must not change what the Go
// analyzer reports.
package main

import (
	"net/http"
)

func main() {
	http.HandleFunc("/gateway/status", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok"))
	})
	http.ListenAndServe(":8080", nil)
}
