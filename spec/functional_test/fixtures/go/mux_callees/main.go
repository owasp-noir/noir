package main

import (
	"net/http"

	"github.com/gorilla/mux"
)

func main() {
	r := mux.NewRouter()
	r.HandleFunc("/users", createUser).Methods("POST")
	r.HandleFunc("/healthz", func(w http.ResponseWriter, req *http.Request) {
		w.Write([]byte("ok"))
	}).Methods("GET")
	r.HandleFunc("/profile", listProfile).Methods("GET")
	http.ListenAndServe(":8080", r)
}
