package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

func listC(w http.ResponseWriter, r *http.Request) {
	_ = r.URL.Query().Get("qc")
}

func main() {
	r := chi.NewRouter()
	r.Get("/a", listA)
	r.Get("/b", listB)
	r.Get("/c", listC)
	http.ListenAndServe(":3000", r)
}

func listA(w http.ResponseWriter, r *http.Request) {
	_ = r.URL.Query().Get("qa")
}

func listB(w http.ResponseWriter, r *http.Request) {
	_ = r.URL.Query().Get("qb")
}
