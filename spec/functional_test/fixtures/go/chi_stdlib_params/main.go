package main

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/render"
	binding "github.com/oapi-codegen/runtime"
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
	r.Post("/stream", func(w http.ResponseWriter, r *http.Request) {
		var order CreateOrder
		decodeOrder(w, r, &order)
	})
	r.Post("/render", func(w http.ResponseWriter, r *http.Request) {
		order := new(CreateOrder)
		_ = render.Bind(r, order)
	})
	r.Get("/cursor", func(w http.ResponseWriter, r *http.Request) {
		var params struct{ Cursor string }
		_ = binding.BindQueryParameterWithOptions("form", true, false, "cursor", r.URL.Query(), &params.Cursor, binding.BindQueryParameterOptions{})
	})
	r.Post("/ignored", func(w http.ResponseWriter, r *http.Request) {
		type CreateOrder struct {
			Internal string `json:"-"`
		}
		var in CreateOrder
		_ = json.NewDecoder(r.Body).Decode(&in)
	})
	r.Post("/bytes", func(w http.ResponseWriter, r *http.Request) {
		order := &CreateOrder{}
		unpack(r, order)
	})
	r.Mount("/admin", adminRouter())
	_ = http.ListenAndServe(":8080", r)
}

func decodeOrder(w http.ResponseWriter, r *http.Request, target any) {
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024))
	_ = dec.Decode(target)
}

func adminRouter() chi.Router {
	r := chi.NewRouter()
	r.Get("/orders", listOrders)
	return r
}
