package main

import (
	"encoding/json"
	"net/http"
)

type server struct {
	mux *http.ServeMux
}

// Not a ServeMux: its Handle is no route.
type worker struct {
	jobs *jobQueue
}

type jobQueue struct{}

func (q *jobQueue) Handle(name string, fn func()) {}

func (s *server) routes() {
	s.mux.HandleFunc("GET /api/users", s.handleUsersList)
	s.mux.HandleFunc("POST /api/users", s.handleUsersCreate())
	s.mux.Handle("GET /api/health", http.HandlerFunc(s.handleHealth))
	s.mux.HandleFunc("/legacy", s.handleHealth)
}

func (w *worker) start() {
	w.jobs.Handle("/sync", func() {})
}

func (s *server) handleUsersList(w http.ResponseWriter, r *http.Request) {
	_ = r.URL.Query().Get("page")
}

func (s *server) handleUsersCreate() http.HandlerFunc {
	type request struct {
		Name string `json:"name"`
	}
	return func(w http.ResponseWriter, r *http.Request) {
		var req request
		_ = json.NewDecoder(r.Body).Decode(&req)
	}
}

func (s *server) handleHealth(w http.ResponseWriter, r *http.Request) {}

func main() {
	s := &server{mux: http.NewServeMux()}
	s.routes()
	_ = http.ListenAndServe(":8080", s.mux)
}
