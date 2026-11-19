package main

import (
	"fmt"
	"net/http"
)

const apiPrefix = "/api/v1"

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /ctl", h)
	mux.HandleFunc(http.MethodGet+" /users", h)
	mux.HandleFunc(http.MethodPost+" /users", h)
	mux.Handle(http.MethodDelete+" /users/{id}", http.HandlerFunc(h))
	mux.HandleFunc(http.MethodPut+" "+apiPrefix+"/items/{id}", h)
	mux.HandleFunc(fmt.Sprintf("%s %s/orders", http.MethodGet, apiPrefix), h)

	_ = http.ListenAndServe(":8080", mux)
}

func h(w http.ResponseWriter, r *http.Request) {}
