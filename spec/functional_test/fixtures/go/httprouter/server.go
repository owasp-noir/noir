package main

import (
	"fmt"
	"net/http"

	"github.com/julienschmidt/httprouter"
)

func main() {
	router := httprouter.New()

	// Basic GET route
	router.GET("/ping", func(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
		name := r.URL.Query().Get("name")
		age := r.FormValue("age")
		fmt.Fprintf(w, "Ping! Name: %s, Age: %s", name, age)
	})

	// POST route with form parameters
	router.POST("/submit", func(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
		username := r.PostFormValue("username")
		userAgent := r.Header.Get("User-Agent")
		fmt.Fprintf(w, "Data: %s, %s", username, userAgent)
	})

	// Route with path parameter
	router.GET("/users/:id", func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		userID := ps.ByName("id")
		fmt.Fprintf(w, "User ID: %s", userID)
	})

	// Route with multiple path parameters
	router.GET("/users/:id/posts/:postid", func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		userID := ps.ByName("id")
		postID := ps.ByName("postid")
		fmt.Fprintf(w, "User: %s, Post: %s", userID, postID)
	})

	// PUT route
	router.PUT("/items/:id", func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		itemID := ps.ByName("id")
		fmt.Fprintf(w, "Updated item: %s", itemID)
	})

	// DELETE route
	router.DELETE("/items/:id", func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		itemID := ps.ByName("id")
		fmt.Fprintf(w, "Deleted item: %s", itemID)
	})

	// PATCH route with query parameter
	router.PATCH("/items/:id/status", func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		itemID := ps.ByName("id")
		status := r.URL.Query().Get("status")
		fmt.Fprintf(w, "Patched item %s: %s", itemID, status)
	})

	// Route with header and cookie extraction
	router.GET("/secure", func(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
		apiKey := r.Header.Get("X-API-Key")
		session, _ := r.Cookie("session_id")
		fmt.Fprintf(w, "Key: %s, Session: %s", apiKey, session.Value)
	})

	http.ListenAndServe(":8080", router)
}
