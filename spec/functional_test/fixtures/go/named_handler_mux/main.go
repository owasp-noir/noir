package main

import (
	"net/http"

	"github.com/gorilla/mux"
)

func listC(w http.ResponseWriter, r *http.Request) {
	_ = r.URL.Query().Get("qc")
}

func main() {
	r := mux.NewRouter()
	r.HandleFunc("/a", listA).Methods("GET")
	r.HandleFunc("/b", listB).Methods("GET")
	r.HandleFunc("/c", listC).Methods("GET")
	http.ListenAndServe(":8000", r)
}

func listA(w http.ResponseWriter, r *http.Request) {
	_ = r.URL.Query().Get("qa")
}

func listB(w http.ResponseWriter, r *http.Request) {
	_ = r.URL.Query().Get("qb")
}
