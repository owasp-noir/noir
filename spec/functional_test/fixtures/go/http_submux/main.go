package main

import (
	"log"
	"net/http"
)

func main() {
	v1 := http.NewServeMux()
	v1.HandleFunc("GET /users/{id}", getUser)
	v1.HandleFunc("POST /users", createUser)

	admin := http.NewServeMux()
	admin.HandleFunc("GET /stats", stats)
	v1.Handle("/admin/", http.StripPrefix("/admin", admin))

	mux := http.NewServeMux()
	mux.Handle("/v1/", http.StripPrefix("/v1", v1))
	mux.HandleFunc("GET /healthz", health)

	log.Fatal(http.ListenAndServe(":8080", mux))
}

func getUser(w http.ResponseWriter, r *http.Request)    {}
func createUser(w http.ResponseWriter, r *http.Request) {}
func stats(w http.ResponseWriter, r *http.Request)      {}
func health(w http.ResponseWriter, r *http.Request)     {}
