package main

import "net/http"

func health(w http.ResponseWriter, r *http.Request) error     { return nil }
func login(w http.ResponseWriter, r *http.Request) error      { return nil }
func listUsers(w http.ResponseWriter, r *http.Request) error  { return nil }
func addUser(w http.ResponseWriter, r *http.Request) error    { return nil }
func listEvents(w http.ResponseWriter, r *http.Request) error { return nil }
func profile(w http.ResponseWriter, r *http.Request) error    { return nil }

func requireAuth(next http.Handler) http.Handler { return next }

func main() {
	r := newRouter()
	r.Get("/health", health)
	r.Post("/login", login)

	r.Route("/admin", func(r *router) {
		r.Get("/users", listUsers)
		r.Post("/users", addUser)
		r.Route("/audit", func(r *router) {
			r.Get("/events", listEvents)
		})
	})

	r.With(requireAuth).Route("/user", func(r *router) {
		r.Get("/profile", profile)
	})

	// Not the wrapper: a key lookup that shares the verb name.
	flags := newStore()
	flags.Get("/flags/beta")

	http.ListenAndServe(":8080", r)
}
