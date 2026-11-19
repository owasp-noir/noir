package main

import (
	"net/http"

	"example.com/chiprefix/internal/handler"
	"github.com/go-chi/chi/v5"
)

func registerOtherFile(r chi.Router) {
	r.Get("/z", handler.Noop)
	r.Get("/find", find)
}

func registerOtherFile2(r chi.Router) {
	r.Get("/z2", handler.Noop)
}

func find(w http.ResponseWriter, r *http.Request) {
	_ = r.URL.Query().Get("term")
}
