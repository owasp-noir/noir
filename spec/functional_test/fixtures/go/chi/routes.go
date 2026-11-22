package main

import (
	"encoding/json"
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

func inputRoutes(r chi.Router) {
	r.Get("/same/search", searchInput); r.Post("/same/save", saveInput)
	r.Get("/split/search", searchInput)
	r.Post("/split/save", saveInput)
	r.Mount("/mounted", mountedInputs())
	r.Mount("/inbox", mailboxRoutes(inbox{}))
	r.Mount("/archive", mailboxRoutes(archive{}))
	r.With(checkInput).Post("/checked", saveInput)
	c := choices{}
	r.Post("/choose", c.choose)
}

func mountedInputs() chi.Router {
	r := chi.NewRouter()
	r.Get("/search", searchInput); r.Post("/save", saveInput)
	return r
}

func searchInput(w http.ResponseWriter, r *http.Request) { r.FormValue("term") }
func saveInput(w http.ResponseWriter, r *http.Request) { r.FormValue("title") }

func checkInput(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var guard struct { Proof string `json:"proof"` }
		json.NewDecoder(r.Body).Decode(&guard)
		next.ServeHTTP(w, r)
	})
}

type choices struct{}

func (c choices) choose(w http.ResponseWriter, r *http.Request) {
	run := c.first
	if r.Header.Get("X-Mode") != "" {
		run = c.second
	}
	run(w, r)
}
func (c choices) first(w http.ResponseWriter, r *http.Request) { r.PostFormValue("first") }
func (c choices) second(w http.ResponseWriter, r *http.Request) { r.PostFormValue("second") }

func metricRoutes(r chi.Router) {
	r.Post("/metrics/write", func(w http.ResponseWriter, r *http.Request) {
		for _, fields := range reports(r) { metric(fields, "rate") }
	})
	r.Get("/metrics/read", func(w http.ResponseWriter, r *http.Request) {
		fields := map[string]any{"rate": 1}
		metric(fields, "rate")
	})
}

func reports(r *http.Request) []map[string]any {
	var fields map[string]any
	json.NewDecoder(r.Body).Decode(&fields)
	return []map[string]any{fields}
}

func metric(fields map[string]any, key string) any { return fields[key] }

type mailbox interface { list(http.ResponseWriter, *http.Request) }
type inbox struct{}
type archive struct{}

func (inbox) list(w http.ResponseWriter, r *http.Request) { r.FormValue("unread") }
func (archive) list(w http.ResponseWriter, r *http.Request) { r.FormValue("year") }

func mailboxRoutes(m mailbox) chi.Router {
	r := chi.NewRouter()
	r.Get("/messages", m.list)
	return r
}
