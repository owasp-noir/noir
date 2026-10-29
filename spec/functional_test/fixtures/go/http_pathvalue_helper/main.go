package main

import "net/http"

func lookup(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("identifier")
	_ = id
	byID(w, r)
}

func byID(w http.ResponseWriter, r *http.Request) { _ = r.PathValue("userID") }

func main() {
	m := http.NewServeMux()
	m.HandleFunc("GET /users/{identifier}", lookup)
	m.HandleFunc("GET /files/{path...}", func(w http.ResponseWriter, r *http.Request) { _ = r.PathValue("path") })
	http.ListenAndServe(":8081", m)
}
