package main

import (
	"fmt"
	"net/http"

	"github.com/gorilla/mux"
)

func main() {
	r := mux.NewRouter()

	r.HandleFunc("/multi", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "multi")
	}).Methods("GET", "POST")

	r.HandleFunc("/filter", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "filter")
	}).Methods("GET").Queries("type", "{type}", "page", "{page}")

	http.ListenAndServe(":8080", r)
}
