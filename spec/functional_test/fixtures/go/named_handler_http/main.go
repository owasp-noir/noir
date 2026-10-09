package main

import "net/http"

func listC(w http.ResponseWriter, r *http.Request) {
	_ = r.URL.Query().Get("qc")
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /a", listA)
	mux.HandleFunc("GET /b", listB)
	mux.HandleFunc("GET /c", listC)
	http.ListenAndServe(":8080", mux)
}

func listA(w http.ResponseWriter, r *http.Request) {
	_ = r.URL.Query().Get("qa")
}

func listB(w http.ResponseWriter, r *http.Request) {
	_ = r.URL.Query().Get("qb")
}
