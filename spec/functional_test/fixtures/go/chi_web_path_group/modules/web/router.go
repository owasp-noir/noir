package web

import "github.com/go-chi/chi/v5"

// A trimmed copy of the shape of gitea's modules/web router wrapper.
type Router struct{ chiRouter chi.Router }

type RouterPathGroup struct{ r *Router }

func NewRouter() *Router { return &Router{chiRouter: chi.NewRouter()} }

func (r *Router) Group(pattern string, fn func(), middlewares ...any) {}

func (r *Router) Get(pattern string, h ...any) {}

func (r *Router) PathGroup(pattern string, fn func(g *RouterPathGroup), h ...any) {}

func (g *RouterPathGroup) MatchPath(methods, pattern string, h ...any) {}
