package ui

import (
	"net/http"
	"strings"
)

type sessionMiddleware struct{}

func newSessionMiddleware() *sessionMiddleware {
	return &sessionMiddleware{}
}

func (m *sessionMiddleware) handle(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if isStatic(r) {
			next.ServeHTTP(w, r)
			return
		}
		if !isAuthenticated(r) && !isPublic(r) {
			http.Redirect(w, r, "/login", http.StatusFound)
			return
		}
		next.ServeHTTP(w, r)
	})
}

type csrfMiddleware struct{}

func newCSRFMiddleware() *csrfMiddleware {
	return &csrfMiddleware{}
}

func (m *csrfMiddleware) handle(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost && r.FormValue("csrf") == "" {
			http.Error(w, "bad csrf", http.StatusBadRequest)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func isAuthenticated(r *http.Request) bool {
	_, err := r.Cookie("session")
	return err == nil
}

func isStatic(r *http.Request) bool {
	return strings.HasPrefix(r.URL.Path, "/static/")
}

func isPublic(r *http.Request) bool {
	path := r.URL.Path

	switch path {
	case "/", "/login",
		"/offline":
		return true
	}

	return isStatic(r) ||
		strings.HasPrefix(path, "/share/")
}
