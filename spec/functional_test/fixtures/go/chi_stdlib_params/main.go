package main

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
)

func main() {
	r := chi.NewRouter()
	r.Get("/orders", listOrders)
	r.Post("/orders", createOrder)
	r.Put("/orders/{id}", updateOrder)
	r.Get("/orders/search", searchOrders)
	r.Post("/inline", func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		_ = q.Get("dry_run")
		var in CreateOrder
		_ = json.NewDecoder(r.Body).Decode(&in)
	})
	r.Mount("/admin", adminRouter())
	_ = http.ListenAndServe(":8080", r)
}

func adminRouter() chi.Router {
	r := chi.NewRouter()
	r.Get("/orders", listOrders)
	return r
}
