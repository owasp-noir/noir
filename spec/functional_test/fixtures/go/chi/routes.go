package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

func setupAdditionalRoutes(r chi.Router) {
	// PATCH method test
	r.Patch("/items/{id}", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("updated"))
	})

	// Nested Route with inline params
	r.Route("/v2", func(r chi.Router) {
		r.Get("/status", func(w http.ResponseWriter, r *http.Request) {
			w.Write([]byte("v2 status"))
		})
		r.Post("/data", func(w http.ResponseWriter, r *http.Request) {
			payload := r.FormValue("payload")
			_ = payload
		})
	})

	// Multiple query and header params
	r.Get("/analytics", func(w http.ResponseWriter, r *http.Request) {
		from := r.URL.Query().Get("from")
		to := r.URL.Query().Get("to")
		apiKey := r.Header.Get("X-Analytics-Key")
		_ = from
		_ = to
		_ = apiKey
	})

	// Cookie-based auth
	r.Get("/dashboard", func(w http.ResponseWriter, r *http.Request) {
		session, _ := r.Cookie("session_token")
		_ = session
	})
}
