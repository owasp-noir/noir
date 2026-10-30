package main

import "net/http"

func h(w http.ResponseWriter, r *http.Request) {}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /exact/{$}", h)
	mux.HandleFunc("GET /reader/api/0/", h)
	mux.HandleFunc("GET /api/v1/users", h)
	http.ListenAndServe(":8080", mux)
}
