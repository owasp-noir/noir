package ui

import "net/http"

type handler struct{}

func Serve() http.Handler {
	session := newSessionMiddleware()
	csrf := newCSRFMiddleware()
	h := &handler{}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /login", h.showLogin)
	mux.HandleFunc("POST /items/{id}/remove", h.removeItem)
	mux.HandleFunc("GET /share/{code}", h.share)
	mux.HandleFunc("GET /static/{file}", h.static)

	return session.handle(csrf.handle(mux))
}

func (h *handler) showLogin(w http.ResponseWriter, r *http.Request) {}

func (h *handler) removeItem(w http.ResponseWriter, r *http.Request) {}

func (h *handler) share(w http.ResponseWriter, r *http.Request) {}

func (h *handler) static(w http.ResponseWriter, r *http.Request) {}
