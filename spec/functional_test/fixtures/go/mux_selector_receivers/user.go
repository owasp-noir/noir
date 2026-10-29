package main

import "net/http"

// Registered from a sibling file, on a struct-field subrouter assigned in main.go.
func (api *API) InitUser() {
	api.BaseRoutes.Users.Handle("/ids", http.HandlerFunc(h)).Methods(http.MethodPost)
	api.BaseRoutes.Users.HandleFunc("/stats", h).Methods(http.MethodGet)
}
