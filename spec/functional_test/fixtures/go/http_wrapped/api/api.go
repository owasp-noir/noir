package api

import "net/http"

type handler struct{}

func NewHandler() http.Handler {
	handler := &handler{}
	mw := newMiddleware()

	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/items", handler.createItem)
	mux.HandleFunc("GET /v1/items/{itemID}", handler.getItem)

	return mw.withCORS(mw.requireKey(mux))
}
