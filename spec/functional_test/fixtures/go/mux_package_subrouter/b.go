package main

import "net/http"

func setup() {
	r = r.PathPrefix("/v1").Subrouter()
	r.HandleFunc("/x", h).Methods("GET")
}

func h(w http.ResponseWriter, r *http.Request) {}
