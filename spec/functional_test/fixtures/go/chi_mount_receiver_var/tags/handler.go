package tags

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

type Handler struct{}

func NewHandler() *Handler { return &Handler{} }

func (h *Handler) Routes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", h.list)
	r.Get("/{slug}", h.get)
	r.Delete("/{slug}", h.remove)
	return r
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request)   {}
func (h *Handler) get(w http.ResponseWriter, r *http.Request)    {}
func (h *Handler) remove(w http.ResponseWriter, r *http.Request) {}
