package main

import "net/http"

func main() {
	mux := http.NewServeMux()
	h := &handler{}

	mux.HandleFunc("GET /{$}", h.index)
	mux.HandleFunc("GET /v1/entries", h.getEntries)
	mux.HandleFunc("POST /v1/entries", h.createEntry)

	http.ListenAndServe(":8080", mux)
}
