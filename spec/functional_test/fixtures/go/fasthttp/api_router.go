package main

import (
	"fmt"

	"github.com/valyala/fasthttp"
)

// Additional router for API v2
type APIRouter struct{}

func (r *APIRouter) GET(path string, handler func(*fasthttp.RequestCtx)) {
	// Router implementation
}

func (r *APIRouter) POST(path string, handler func(*fasthttp.RequestCtx)) {
	// Router implementation
}

func (r *APIRouter) PUT(path string, handler func(*fasthttp.RequestCtx)) {
	// Router implementation
}

func (r *APIRouter) PATCH(path string, handler func(*fasthttp.RequestCtx)) {
	// Router implementation
}

func (r *APIRouter) DELETE(path string, handler func(*fasthttp.RequestCtx)) {
	// Router implementation
}

func setupAPIRoutes() {
	api := &APIRouter{}

	// PATCH method test
	api.PATCH("/items/:id", func(ctx *fasthttp.RequestCtx) {
		itemId := ctx.UserValue("id")
		name := ctx.FormValue("name")
		fmt.Fprintf(ctx, "Patched item %s: %s", itemId, name)
	})

	// Multiple path params
	api.GET("/shops/:shopId/items/:itemId", func(ctx *fasthttp.RequestCtx) {
		shopId := ctx.UserValue("shopId")
		itemId := ctx.UserValue("itemId")
		detail := ctx.QueryArgs().Peek("detail")
		fmt.Fprintf(ctx, "Shop %s, Item %s, Detail: %s", shopId, itemId, detail)
	})

	// POST with combined form and header
	api.POST("/upload", func(ctx *fasthttp.RequestCtx) {
		fileName := ctx.FormValue("file_name")
		contentType := ctx.Request.Header.Peek("Content-Type")
		authToken := ctx.Request.Header.Cookie("auth_token")
		fmt.Fprintf(ctx, "Uploaded %s, CT: %s, Auth: %s", fileName, contentType, authToken)
	})

	// DELETE with header
	api.DELETE("/cache/:key", func(ctx *fasthttp.RequestCtx) {
		key := ctx.UserValue("key")
		adminKey := ctx.Request.Header.Peek("X-Admin-Key")
		fmt.Fprintf(ctx, "Deleted cache %s with key %s", key, adminKey)
	})
}
