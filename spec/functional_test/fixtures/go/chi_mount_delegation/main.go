package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"example.com/shop/api"
	"example.com/shop/handlers"
)

func main() {
	r := chi.NewRouter()
	r.Mount("/api", api.Handler(api.Impl{}))
	r.Mount("/v2/", handlers.New().Handler())
	http.ListenAndServe(":8080", r)
}
