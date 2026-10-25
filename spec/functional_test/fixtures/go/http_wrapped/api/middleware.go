package api

import (
	"net/http"

	"example.com/app/response"
)

type middleware struct{}

func newMiddleware() *middleware {
	return &middleware{}
}

func (m *middleware) withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (m *middleware) requireKey(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Auth-Token") == "" {
			response.Unauthorized(w, r)
			return
		}
		next.ServeHTTP(w, r)
	})
}
