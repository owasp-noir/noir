package main

import (
	"database/sql"
	"net/http"

	"gorm.io/gorm"
)

var (
	db     *sql.DB
	gormDB *gorm.DB
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /orders/{id}", getOrder)
	mux.HandleFunc("GET /orders", listOrders)
	mux.HandleFunc("DELETE /orders/{id}", deleteOrder)
	mux.HandleFunc("GET /reports/{name}", report)
	mux.HandleFunc("GET /health", health)
	mux.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.Dir("static"))))
	http.ListenAndServe(":8080", mux)
}

func getOrder(w http.ResponseWriter, r *http.Request) {
	db.QueryRow("SELECT * FROM orders WHERE id = " + r.PathValue("id"))
}

func listOrders(w http.ResponseWriter, r *http.Request) {
	db.QueryContext(r.Context(), "SELECT * FROM orders ORDER BY "+r.URL.Query().Get("sort"))
}

func deleteOrder(w http.ResponseWriter, r *http.Request) {
	db.ExecContext(r.Context(), "DELETE FROM orders WHERE id = "+r.PathValue("id"))
}

func report(w http.ResponseWriter, r *http.Request) {
	var rows []map[string]any
	gormDB.Raw("SELECT * FROM " + r.PathValue("name")).Scan(&rows)
}

func health(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
}
