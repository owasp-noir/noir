package main

import (
	"fmt"
	"log"

	"github.com/valyala/fasthttp"
)

func main() {
	// Create a new fasthttp router
	router := &fasthttp.Server{
		Handler: requestHandler,
	}

	log.Fatal(router.ListenAndServe(":8080"))
}

func requestHandler(ctx *fasthttp.RequestCtx) {
	switch string(ctx.Path()) {
	case "/":
		indexHandler(ctx)
	case "/users":
		if ctx.IsGet() {
			getUsersHandler(ctx)
		} else if ctx.IsPost() {
			createUserHandler(ctx)
		}
	case "/products":
		if ctx.IsGet() {
			getProductsHandler(ctx)
		} else if ctx.IsPost() {
			createProductHandler(ctx)
		}
	case "/admin":
		adminHandler(ctx)
	default:
		// Check for user path pattern /users/:id
		path := string(ctx.Path())
		if len(path) > 7 && path[:7] == "/users/" {
			getUserHandler(ctx)
		} else {
			ctx.Error("Not found", fasthttp.StatusNotFound)
		}
	}
}

func indexHandler(ctx *fasthttp.RequestCtx) {
	// Query parameter access
	name := ctx.QueryArgs().Peek("name")
	age := ctx.QueryArgs().Peek("age")
	
	// Header access
	userAgent := ctx.Request.Header.Peek("User-Agent")
	apiKey := ctx.Request.Header.Peek("X-API-Key")
	
	ctx.SetContentType("application/json")
	fmt.Fprintf(ctx, `{"message": "Hello", "name": "%s", "age": "%s", "userAgent": "%s", "apiKey": "%s"}`, 
		name, age, userAgent, apiKey)
}

func getUsersHandler(ctx *fasthttp.RequestCtx) {
	// Query parameters
	limit := ctx.QueryArgs().Peek("limit")
	offset := ctx.QueryArgs().Peek("offset")
	filter := ctx.QueryArgs().Peek("filter")
	
	// Headers
	authToken := ctx.Request.Header.Peek("Authorization")
	
	ctx.SetContentType("application/json")
	fmt.Fprintf(ctx, `{"users": [], "limit": "%s", "offset": "%s", "filter": "%s", "auth": "%s"}`, 
		limit, offset, filter, authToken)
}

func createUserHandler(ctx *fasthttp.RequestCtx) {
	// Form data access
	username := ctx.FormValue("username")
	email := ctx.FormValue("email")
	password := ctx.FormValue("password")
	
	// Post args access
	role := ctx.PostArgs().Peek("role")
	department := ctx.PostArgs().Peek("department")
	
	// Headers
	contentType := ctx.Request.Header.Peek("Content-Type")
	clientId := ctx.Request.Header.Peek("X-Client-ID")
	
	ctx.SetContentType("application/json")
	fmt.Fprintf(ctx, `{"created": true, "username": "%s", "email": "%s", "role": "%s", "department": "%s", "contentType": "%s", "clientId": "%s"}`, 
		username, email, role, department, contentType, clientId)
}

func getUserHandler(ctx *fasthttp.RequestCtx) {
	// Path parameter (simulated with UserValue)
	userId := ctx.UserValue("userId")
	
	// Query parameters
	fields := ctx.QueryArgs().Peek("fields")
	
	// Headers
	acceptLang := ctx.Request.Header.Peek("Accept-Language")
	
	ctx.SetContentType("application/json")
	fmt.Fprintf(ctx, `{"user": {"id": "%s"}, "fields": "%s", "lang": "%s"}`, 
		userId, fields, acceptLang)
}

func getProductsHandler(ctx *fasthttp.RequestCtx) {
	// Query parameters
	category := ctx.QueryArgs().Peek("category")
	priceMin := ctx.QueryArgs().Peek("price_min")
	priceMax := ctx.QueryArgs().Peek("price_max")
	
	// Headers
	storeId := ctx.Request.Header.Peek("X-Store-ID")
	
	ctx.SetContentType("application/json")
	fmt.Fprintf(ctx, `{"products": [], "category": "%s", "priceMin": "%s", "priceMax": "%s", "storeId": "%s"}`, 
		category, priceMin, priceMax, storeId)
}

func createProductHandler(ctx *fasthttp.RequestCtx) {
	// Form values
	name := ctx.FormValue("name")
	price := ctx.FormValue("price")
	
	// Post args
	description := ctx.PostArgs().Peek("description")
	tags := ctx.PostArgs().Peek("tags")
	
	// Headers
	vendorId := ctx.Request.Header.Peek("X-Vendor-ID")
	
	ctx.SetContentType("application/json")
	fmt.Fprintf(ctx, `{"created": true, "name": "%s", "price": "%s", "description": "%s", "tags": "%s", "vendorId": "%s"}`, 
		name, price, description, tags, vendorId)
}

func adminHandler(ctx *fasthttp.RequestCtx) {
	// Cookie access
	sessionId := ctx.Request.Header.Cookie("session_id")
	adminToken := ctx.Request.Header.Cookie("admin_token")
	
	// Query parameters
	action := ctx.QueryArgs().Peek("action")
	
	// Headers
	adminKey := ctx.Request.Header.Peek("X-Admin-Key")
	
	ctx.SetContentType("application/json")
	fmt.Fprintf(ctx, `{"admin": true, "sessionId": "%s", "adminToken": "%s", "action": "%s", "adminKey": "%s"}`, 
		sessionId, adminToken, action, adminKey)
}