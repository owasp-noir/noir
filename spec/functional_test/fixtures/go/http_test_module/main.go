package main

import "net/http"

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /orders/{id}", getOrder)
	http.ListenAndServe(":8080", mux)
}

func getOrder(w http.ResponseWriter, r *http.Request) {
	w.Write([]byte(r.PathValue("id")))
}
