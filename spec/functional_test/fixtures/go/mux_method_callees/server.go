package main

import (
	"net/http"

	"github.com/gorilla/mux"
)

type API struct{}

func (a *API) ListUsers(w http.ResponseWriter, r *http.Request) {
	users := fetchUsers()
	w.Write([]byte(users))
}

func (a *API) GetUser(w http.ResponseWriter, r *http.Request) {
	_ = mux.Vars(r)["id"]
}

// Middleware wrapper — handlers are commonly registered wrapped
// (gophish's `mid.Use(as.Foo, ...)`); the real handler is the first
// argument and must be unwrapped for callee resolution.
func wrap(h http.HandlerFunc) http.HandlerFunc {
	return h
}

func main() {
	a := &API{}
	r := mux.NewRouter()
	// Bare method-value handler.
	r.HandleFunc("/users", a.ListUsers).Methods("GET")
	// Wrapped method-value handler.
	r.HandleFunc("/users/{id}", wrap(a.GetUser)).Methods("GET")
	http.ListenAndServe(":8080", r)
}

func fetchUsers() string {
	return ""
}
