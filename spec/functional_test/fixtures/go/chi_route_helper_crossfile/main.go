package main

import (
	"net/http"

	"example.com/chiprefix/internal/api"
	"example.com/chiprefix/internal/handler"
	"github.com/go-chi/chi/v5"
)

func main() {
	r := chi.NewRouter()

	// Route callbacks declared in another package and in another file.
	r.Route("/c1-pkg", api.Register)
	r.Route("/c2-otherfile", registerOtherFile)
	// Closures handing their router to such helpers.
	r.Route("/c3-closure-otherfile", func(r chi.Router) {
		registerOtherFile2(r)
	})
	r.Route("/c4-closure-pkg", func(r chi.Router) {
		api.Register2(r)
	})
	// A sub-router mounted by name next to the `func(r chi.Router)` closures.
	sub := chi.NewRouter()
	sub.Get("/s", handler.Noop)
	r.Mount("/c5-mount-var", sub)
	r.Route("/c6-closure-samefile", func(r chi.Router) {
		registerSameFile(r)
	})
	// The same helper under a second prefix.
	r.Route("/c8-again", registerOtherFile2)
	// A group adds no prefix.
	r.Group(api.Register3)

	_ = http.ListenAndServe(":3000", r)
}

func registerSameFile(r chi.Router) {
	r.Get("/same", handler.Noop)
}
