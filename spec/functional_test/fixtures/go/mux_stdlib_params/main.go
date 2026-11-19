package main

import (
	"net/http"

	"github.com/gorilla/mux"
)

func main() {
	r := mux.NewRouter()
	r.HandleFunc("/orders", listOrders).Methods("GET")
	r.HandleFunc("/orders", createOrder).Methods("POST")
	r.HandleFunc("/orders/{id}", updateOrder).Methods("PUT")
	r.HandleFunc("/orders/search", searchOrders).Methods("GET")
	_ = http.ListenAndServe(":8080", r)
}
