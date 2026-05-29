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
	r.Methods("POST").
		Path("/builder-users").
		HandlerFunc(createUser)
	r.Path("/builder-healthz").
		Methods("GET").
		Handler(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
			w.Write([]byte("builder-ok"))
		}))
	http.ListenAndServe(":8080", r)
}
