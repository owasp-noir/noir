package main

import "net/http"

// Parser input for the project's own tests; `go build ./...` never compiles it.
func main() {
	http.HandleFunc("GET /fake/testdata", func(w http.ResponseWriter, r *http.Request) {})
}
