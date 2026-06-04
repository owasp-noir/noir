package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

func main() {
	r := chi.NewRouter()

	r.Get("/", index)
	// MethodFunc: HTTP method as the first string argument.
	r.MethodFunc("GET", "/health", health)
	r.MethodFunc("POST", "/submit", submit)
	// HandleFunc / Handle: match every HTTP method.
	r.HandleFunc("/everything", everything)

	// Mount struct value-method routers (chi's REST "resource" pattern).
	r.Mount("/todos", todosResource{}.Routes())
	r.Mount("/users", usersResource{}.Routes())

	http.ListenAndServe(":3333", r)
}

func index(w http.ResponseWriter, r *http.Request)      {}
func health(w http.ResponseWriter, r *http.Request)     {}
func submit(w http.ResponseWriter, r *http.Request)     {}
func everything(w http.ResponseWriter, r *http.Request) {}
