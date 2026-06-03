package app

import (
	"goyave.dev/goyave/v5"
)

type Controller struct {
	goyave.Component
}

// Mirrors go-goyave/goyave-blog-example: a prefixed subrouter, then
// fluent `Group().SetMeta(...)` / `Group()` children that must inherit
// the parent prefix. The `.SetMeta(...)` tail has to be peeled so the
// child binds to `/articles`, not `/`.
func (c *Controller) RegisterRoutes(router *goyave.Router) {
	subrouter := router.Subrouter("/articles")
	subrouter.Get("/", c.Index)
	subrouter.Get("/{slug}", c.Show)

	authRouter := subrouter.Group().SetMeta("auth", true)
	authRouter.Post("/", c.Create)

	ownedRouter := authRouter.Group()
	ownedRouter.Patch("/{articleID:[0-9]+}", c.Update)
	ownedRouter.Delete("/{articleID:[0-9]+}", c.Delete)
}

func (c *Controller) Index(response *goyave.Response, request *goyave.Request) {
	listArticles()
}

func (c *Controller) Show(response *goyave.Response, request *goyave.Request)   {}
func (c *Controller) Create(response *goyave.Response, request *goyave.Request) {}
func (c *Controller) Update(response *goyave.Response, request *goyave.Request) {}
func (c *Controller) Delete(response *goyave.Response, request *goyave.Request) {}

func listArticles() {}
