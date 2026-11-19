package main

import "net/http"

type route struct {
	pattern string
	handler http.HandlerFunc
}

func main() {
	mux := http.NewServeMux()
	routes := []route{
		{"GET /users", listUsers},
		{"POST /users", createUser},
		{pattern: "DELETE /users/{id}", handler: deleteUser},
	}
	for _, rt := range routes {
		mux.HandleFunc(rt.pattern, rt.handler)
	}
	_ = http.ListenAndServe(":8080", mux)
}

func listUsers(w http.ResponseWriter, r *http.Request)  { _ = r.URL.Query().Get("page") }
func createUser(w http.ResponseWriter, r *http.Request) { _ = r.FormValue("name") }
func deleteUser(w http.ResponseWriter, r *http.Request) {}
