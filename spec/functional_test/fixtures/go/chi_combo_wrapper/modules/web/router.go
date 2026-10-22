package web

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

// Router is a thin wrapper over chi in the style of gitea's modules/web:
// it adds Combo (one path, chained verbs) and Methods (a comma-separated
// method list) on top of the chi verbs.
type Router struct {
	chiRouter chi.Router
}

func NewRouter() *Router {
	return &Router{chiRouter: chi.NewRouter()}
}

func (r *Router) Get(pattern string, h ...any)    {}
func (r *Router) Post(pattern string, h ...any)   {}
func (r *Router) Put(pattern string, h ...any)    {}
func (r *Router) Delete(pattern string, h ...any) {}
func (r *Router) Methods(methods, pattern string, h ...any) {}
func (r *Router) Group(pattern string, fn func(), middlewares ...any) {}

type Combo struct{}

func (r *Router) Combo(pattern string, h ...any) *Combo { return &Combo{} }
func (c *Combo) Get(h ...any) *Combo                    { return c }
func (c *Combo) Post(h ...any) *Combo                   { return c }
func (c *Combo) Put(h ...any) *Combo                    { return c }
func (c *Combo) Delete(h ...any) *Combo                 { return c }

func (r *Router) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	r.chiRouter.ServeHTTP(w, req)
}
