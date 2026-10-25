package jobs

import (
	"encoding/json"
	"net/http"
)

func Handler(token string) http.Handler {
	mux := http.NewServeMux()
	auth := authMiddleware(token)
	mux.HandleFunc("POST /jobs/run", auth(handleRun()))
	return mux
}

type runRequest struct {
	Script string `json:"script"`
	Cwd    string
}

func handleRun() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req runRequest
		_ = json.NewDecoder(r.Body).Decode(&req)
	}
}

func authMiddleware(token string) func(http.HandlerFunc) http.HandlerFunc {
	return func(next http.HandlerFunc) http.HandlerFunc {
		if token == "" {
			return next
		}
		return func(w http.ResponseWriter, r *http.Request) {
			if r.Header.Get("Authorization") != "Bearer "+token {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}
			next(w, r)
		}
	}
}
