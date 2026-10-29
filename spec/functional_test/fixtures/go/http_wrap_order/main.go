package main

import (
	"net/http"
	"strings"
)

func main() {
	mux := http.NewServeMux()
	mux.Handle("/armfirst", authArmFirst(http.HandlerFunc(list)))
	mux.Handle("/switchpublic", authSwitchPublic(http.HandlerFunc(list)))
	mux.Handle("/multilineif", authMultiLineIf(http.HandlerFunc(list)))
	mux.Handle("/csrfsess", authSessOrCSRF(http.HandlerFunc(list)))
	mux.Handle("/csrfchain", authCSRFChain(http.HandlerFunc(list)))
	mux.Handle("/deferrecover", recoverForbidden(http.HandlerFunc(list)))
	mux.Handle("/plain", authPlain(http.HandlerFunc(list)))
	mux.HandleFunc("/loginreq", loginWithReq(authenticate))
	http.ListenAndServe(":8080", mux)
}

// Control: an ordinary guard.
func authPlain(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") == "" {
			http.Error(w, "no", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// Hands on inside an if arm, refuses after it.
func authArmFirst(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "" {
			next.ServeHTTP(w, r)
			return
		}
		http.Error(w, "no", http.StatusUnauthorized)
	})
}

// Public paths skipped through a switch case, then a real check.
func authSwitchPublic(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/login", "/healthz":
			next.ServeHTTP(w, r)
			return
		}
		if r.Header.Get("Authorization") == "" {
			http.Error(w, "no", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// Public paths skipped through an if whose condition spans two lines.
func authMultiLineIf(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/public/") ||
			r.URL.Path == "/healthz" {
			next.ServeHTTP(w, r)
			return
		}
		if r.Header.Get("Authorization") == "" {
			http.Error(w, "no", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func sessionOf(r *http.Request) *string { return nil }
func csrfOK(r *http.Request) bool       { return true }

// A real session check that also tests CSRF in the same condition.
func authSessOrCSRF(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		sess := sessionOf(r)
		if sess == nil || !csrfOK(r) {
			http.Error(w, "no", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// CSRF arm first, then the session arm of the same chain.
func authCSRFChain(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "POST" && !csrfOK(r) {
			http.Error(w, "csrf", http.StatusForbidden)
			return
		} else if sessionOf(r) == nil {
			http.Error(w, "no", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// Recovers a panic into a 403: runs after the handler, refuses no one up front.
func recoverForbidden(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				http.Error(w, "forbidden", http.StatusForbidden)
			}
		}()
		next.ServeHTTP(w, r)
	})
}

type User struct{}

func authenticate(r *http.Request) (*User, bool) { return nil, false }

// Login factory taking a request-shaped callback.
func loginWithReq(auth func(*http.Request) (*User, bool)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u, ok := auth(r)
		if !ok {
			http.Error(w, "bad password", http.StatusUnauthorized)
			return
		}
		_ = u
		w.WriteHeader(http.StatusOK)
	}
}

func list(w http.ResponseWriter, r *http.Request) {}
