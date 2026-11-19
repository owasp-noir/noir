package main

import (
	"encoding/json"
	"net/http"
)

type LoginReq struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type TransferReq struct {
	From   string `json:"from_account"`
	To     string `json:"to_account"`
	Amount int    `json:"amount"`
}

type CommentReq struct {
	Text string `json:"text"`
}

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("POST /login", func(w http.ResponseWriter, r *http.Request) {
		var req LoginReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
	})

	mux.HandleFunc("POST /transfer", func(w http.ResponseWriter, r *http.Request) {
		var req TransferReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
	})

	mux.HandleFunc("POST /comment", func(w http.ResponseWriter, r *http.Request) {
		req := CommentReq{}
		_ = json.NewDecoder(r.Body).Decode(&req)
	})

	_ = http.ListenAndServe(":8080", mux)
}
