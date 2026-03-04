package main

import (
	"fmt"
	"net/http"

	"github.com/gorilla/mux"
)

func setupAdditionalRoutes(r *mux.Router) {
	// PUT method test
	r.HandleFunc("/items/{id}", func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		itemID := vars["id"]
		fmt.Fprintf(w, "Updated item: %s", itemID)
	}).Methods("PUT")

	// DELETE method test
	r.HandleFunc("/items/{id}", func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		itemID := vars["id"]
		fmt.Fprintf(w, "Deleted item: %s", itemID)
	}).Methods("DELETE")

	// PATCH method test
	r.HandleFunc("/items/{id}/status", func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		itemID := vars["id"]
		status := r.FormValue("status")
		fmt.Fprintf(w, "Patched item %s: %s", itemID, status)
	}).Methods("PATCH")

	// Multiple path variables with query param
	r.HandleFunc("/shops/{shopId}/products/{productId}", func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		shopID := vars["shopId"]
		productID := vars["productId"]
		detail := r.URL.Query().Get("detail")
		fmt.Fprintf(w, "Shop: %s, Product: %s, Detail: %s", shopID, productID, detail)
	}).Methods("GET")

	// Header and cookie extraction
	r.HandleFunc("/secure", func(w http.ResponseWriter, r *http.Request) {
		apiKey := r.Header.Get("X-API-Key")
		session, _ := r.Cookie("session_id")
		fmt.Fprintf(w, "Key: %s, Session: %s", apiKey, session.Value)
	}).Methods("GET")

	// Nested subrouters
	v2 := r.PathPrefix("/v2/").Subrouter()
	v2.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "v2 healthy")
	}).Methods("GET")
}
