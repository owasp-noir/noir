package main

import "net/http"

func main() {
	http.HandleFunc("GET /real", func(w http.ResponseWriter, r *http.Request) {})
	http.ListenAndServe(":8080", nil)
}
