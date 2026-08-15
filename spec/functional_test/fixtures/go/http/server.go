package main

import (
	"encoding/json"
	"fmt"
	"net/http"
)

func main() {
	// Direct on default package — modern pattern (known verb)
	http.HandleFunc("GET /hello", func(w http.ResponseWriter, r *http.Request) {
		name := r.URL.Query().Get("name")
		fmt.Fprintf(w, "Hello %s", name)
	})

	// Explicit mux var (most common real-world shape) — POST + body + header
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/users", func(w http.ResponseWriter, r *http.Request) {
		// body read
		var v map[string]any
		_ = json.NewDecoder(r.Body).Decode(&v)
		ua := r.Header.Get("User-Agent")
		fmt.Fprintf(w, "users %s", ua)
	})

	// Using Handle (not HandleFunc) — with cookie
	mux.Handle("GET /api/health", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c, _ := r.Cookie("session")
		fmt.Fprintf(w, "ok %s", c.Value)
	}))

	// Another modern pattern for form param (POST)
	mux.HandleFunc("POST /items", func(w http.ResponseWriter, r *http.Request) {
		_ = r.FormValue("title")
		w.WriteHeader(201)
	})

	// Go 1.22 pattern for HTTP QUERY (RFC 10008)
	mux.HandleFunc("QUERY /search", func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query().Get("q")
		fmt.Fprintf(w, "query %s", q)
	})

	// Pre-1.22 manual dispatch on r.Method switch
	http.HandleFunc("/query-manual", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case "QUERY":
			filter := r.URL.Query().Get("filter")
			fmt.Fprintf(w, "query %s", filter)
		}
	})

	http.ListenAndServe(":8080", mux)
}
