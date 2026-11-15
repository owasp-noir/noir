package main

import (
  "gitea.dev/modules/web"
  _ "github.com/go-chi/chi/v5"
)

func checkpoint() func(ctx *Context) {
	return func(ctx *Context) {
		if ctx.IsSigned {
			return
		}
		ctx.Error(401)
	}
}

func routes(r *web.Router) {
	r.Group("/secure", func() {
		r.Get("/items", h)
		r.Group("/nested", func() {
			r.Get("/items", h)
		})
	}, checkpoint())
	r.Group("/matched", func() {
		r.Get("/items", h)
	}, AuthUnknown())
	r.Get("/public", h)
}

type Context struct{ IsSigned bool }
func (ctx *Context) Error(code int) {}
func h(ctx *Context) {}
