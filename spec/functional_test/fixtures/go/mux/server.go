package main

import (
	"fmt"
	"net/http"

	"github.com/gorilla/mux"
)

func main() {
	r := mux.NewRouter()

	// Basic route handlers
	r.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) {
		name := r.URL.Query().Get("name")
		age := r.FormValue("age")
		fmt.Fprintf(w, "Ping! Name: %s, Age: %s", name, age)
	}).Methods("GET")

	r.HandleFunc("/admin", func(w http.ResponseWriter, r *http.Request) {
		cookie, _ := r.Cookie("auth_token")
		fmt.Fprintf(w, "Admin access with token: %s", cookie.Value)
	}).Methods("GET")

	r.HandleFunc("/submit", func(w http.ResponseWriter, r *http.Request) {
		username := r.PostFormValue("username")
		password := r.FormValue("password")
		userAgent := r.Header.Get("User-Agent")
		fmt.Fprintf(w, "Data: %s, %s, %s", username, password, userAgent)
	}).Methods("POST")

	// Path variables
	r.HandleFunc("/users/{id}", func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		userID := vars["id"]
		fmt.Fprintf(w, "User ID: %s", userID)
	}).Methods("GET")

	r.HandleFunc("/users/{id}/posts/{postid}", func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		userID := vars["id"]
		postID := vars["postid"]
		fmt.Fprintf(w, "User: %s, Post: %s", userID, postID)
	}).Methods("GET")

	// Subrouters
	api := r.PathPrefix("/api/").Subrouter()
	api.HandleFunc("/status", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "API Status")
	}).Methods("GET")

	v1 := api.PathPrefix("/v1/").Subrouter()
	v1.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Health Check")
	}).Methods("GET")

	// Static file serving
	r.PathPrefix("/static/").Handler(http.StripPrefix("/static/", http.FileServer(http.Dir("./static/"))))

	// Test multi-line route definition
	r.HandleFunc(
		"/multiline",
		func(w http.ResponseWriter, r *http.Request) {
			fmt.Fprintf(w, "multiline")
		},
	).Methods("GET")

	// Handler route and route-builder chains common in larger mux apps
	r.Handle("/handler-route", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "handler route")
	})).Methods("POST").Name("handler.create")

	r.Methods("PATCH").Path("/builder-route").HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "builder route")
	})

	r.Path("/builder-query").Methods("GET").Queries("type", "{type}").HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "builder query")
	})

	// Idiomatic http.MethodX constant form (portainer-style) — the
	// constant must resolve to the verb instead of falling back to GET.
	r.Handle("/profile", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "profile update")
	})).Methods(http.MethodPut)

	r.HandleFunc("/profile", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "profile view")
	}).Methods(http.MethodGet, http.MethodHead)

	http.ListenAndServe(":8080", r)
}
