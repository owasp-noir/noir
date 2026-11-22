package main

import (
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"

	"example.com/shop/api"
	"example.com/shop/handlers"
)

func main() {
	r := chi.NewRouter()
	r.Mount("/api", api.Handler(api.Impl{}))
	r.Mount("/configured", api.Configured(api.Impl{}))
	r.Route(os.Getenv("PREFIX")+"/tenant", func(r chi.Router) {
		r.Mount("/nested", api.Handler(api.Impl{}))
	})
	r.Mount("/v2/", handlers.New().Handler())
	http.ListenAndServe(":8080", r)
}
