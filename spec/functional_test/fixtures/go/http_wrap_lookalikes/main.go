package main

import (
	"net/http"

	amw "example.com/nh/a/mw"
	"example.com/nh/b/mw"
)

// Lookalikes of a guard wrapping a ServeMux handler: only /dup2 is
// guarded (a/mw.Wrap refuses; b/mw.Wrap only passes on).
func main() {
	mux := http.NewServeMux()
	mux.Handle("/csrf", withCSRF(http.HandlerFunc(list)))
	mux.HandleFunc("/login", loginWith(checkPassword))
	mux.Handle("/dup", mw.Wrap(http.HandlerFunc(list)))
	mux.Handle("/dup2", amw.Wrap(http.HandlerFunc(list)))
	mux.HandleFunc("/errmap", handle(list))
	mux.HandleFunc("/errmap2", handle2(list))
	http.ListenAndServe(":8080", mux)
}

func withCSRF(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-CSRF-Token") != "expected" {
			http.Error(w, "csrf", http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// Login handler factory taking a password-check callback: wraps no handler.
func loginWith(verify func(string) bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !verify(r.FormValue("password")) {
			http.Error(w, "bad", http.StatusUnauthorized)
			return
		}
		w.WriteHeader(http.StatusOK)
	}
}

// Error mapper: 401 only for the handler's own error.
func handle(fn func(w http.ResponseWriter, r *http.Request) error) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := fn(w, r); err != nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
		}
	}
}

// Error-path 401 after the handler ran.
func handle2(fn http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		fn(w, r)
		if w.Header().Get("X-Err") == "auth" {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
		}
	}
}

func checkPassword(p string) bool { return p == "x" }

func list(w http.ResponseWriter, r *http.Request) {}
