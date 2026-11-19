package api

import (
	"example.com/chiprefix/internal/handler"
	"github.com/go-chi/chi/v5"
)

func Register(r chi.Router) {
	r.Get("/items", handler.Noop)
}

func Register2(r chi.Router) {
	r.Get("/items2", handler.Noop)
}

func Register3(r chi.Router) {
	r.Get("/c7-items3", handler.Noop)
}
