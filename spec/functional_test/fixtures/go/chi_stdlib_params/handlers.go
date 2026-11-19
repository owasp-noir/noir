package main

import (
	"encoding/json"
	"net/http"
)

type CreateOrder struct {
	SKU      string `json:"sku"`
	Quantity int    `json:"quantity"`
	Coupon   string `json:"coupon,omitempty"`
}

// query string read through a local alias
func listOrders(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	page := q.Get("page")
	limit := q.Get("limit")
	_ = q["tag"]
	if q.Has("debug") {
	}
	_, _ = page, limit
}

// JSON body decoded into a struct
func createOrder(w http.ResponseWriter, r *http.Request) {
	var in CreateOrder
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
}

// parsed form maps
func updateOrder(w http.ResponseWriter, r *http.Request) {
	_ = r.ParseForm()
	_ = r.PostForm.Get("status")
	_ = r.Form.Get("note")
	_ = r.Form["labels"]
}

// several reads on one line
func searchOrders(w http.ResponseWriter, r *http.Request) {
	from, to := r.URL.Query().Get("from"), r.URL.Query().Get("to")
	_, _ = from, to
}
