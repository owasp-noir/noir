package main

import (
	"fmt"
	"log"

	"github.com/valyala/fasthttp"
)

// Router interface for demonstration
type Router struct{}

func (r *Router) GET(path string, handler func(*fasthttp.RequestCtx)) {
	// Router implementation would be here
}

func (r *Router) POST(path string, handler func(*fasthttp.RequestCtx)) {
	// Router implementation would be here
}

func (r *Router) PUT(path string, handler func(*fasthttp.RequestCtx)) {
	// Router implementation would be here
}

func (r *Router) DELETE(path string, handler func(*fasthttp.RequestCtx)) {
	// Router implementation would be here
}

func main() {
	router := &Router{}

	// Basic routes with parameter access
	router.GET("/", func(ctx *fasthttp.RequestCtx) {
		name := ctx.QueryArgs().Peek("name")
		age := ctx.QueryArgs().Peek("age")
		userAgent := ctx.Request.Header.Peek("User-Agent")
		apiKey := ctx.Request.Header.Peek("X-API-Key")
		
		fmt.Fprintf(ctx, "Hello %s, age %s", name, age)
	})

	router.POST("/users", func(ctx *fasthttp.RequestCtx) {
		username := ctx.FormValue("username")
		email := ctx.FormValue("email")
		password := ctx.PostArgs().Peek("password")
		role := ctx.PostArgs().Peek("role")
		contentType := ctx.Request.Header.Peek("Content-Type")
		clientId := ctx.Request.Header.Peek("X-Client-ID")
		
		fmt.Fprintf(ctx, "Created user %s with email %s", username, email)
	})

	router.GET("/users/:id", func(ctx *fasthttp.RequestCtx) {
		userId := ctx.UserValue("id")
		fields := ctx.QueryArgs().Peek("fields")
		acceptLang := ctx.Request.Header.Peek("Accept-Language")
		
		fmt.Fprintf(ctx, "User %s", userId)
	})

	router.PUT("/products/:id", func(ctx *fasthttp.RequestCtx) {
		productId := ctx.UserValue("id")
		name := ctx.FormValue("name")
		price := ctx.FormValue("price")
		vendorId := ctx.Request.Header.Peek("X-Vendor-ID")
		
		fmt.Fprintf(ctx, "Updated product %s", productId)
	})

	router.DELETE("/products/:id", func(ctx *fasthttp.RequestCtx) {
		productId := ctx.UserValue("id")
		adminKey := ctx.Request.Header.Peek("X-Admin-Key")
		
		fmt.Fprintf(ctx, "Deleted product %s", productId)
	})

	router.GET("/admin", func(ctx *fasthttp.RequestCtx) {
		sessionId := ctx.Request.Header.Cookie("session_id")
		adminToken := ctx.Request.Header.Cookie("admin_token")
		action := ctx.QueryArgs().Peek("action")
		adminKey := ctx.Request.Header.Peek("X-Admin-Key")
		
		fmt.Fprintf(ctx, "Admin panel")
	})

	log.Fatal(fasthttp.ListenAndServe(":8080", nil))
}