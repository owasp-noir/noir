package main

import (
	"net/http"

	"github.com/zeromicro/go-zero/rest"
	"github.com/zeromicro/go-zero/rest/httpx"
)

func main() {
	server := rest.MustNewServer(rest.RestConf{
		ServiceConf: service.ServiceConf{
			Name: "example",
		},
		Host: "localhost",
		Port: 8888,
	})
	defer server.Stop()

	// Basic routes
	server.AddRoute(rest.Route{
		Method:  http.MethodGet,
		Path:    "/",
		Handler: homeHandler,
	})

	server.AddRoute(rest.Route{
		Method:  http.MethodGet,
		Path:    "/users/:id",
		Handler: getUserHandler,
	})

	server.AddRoute(rest.Route{
		Method:  http.MethodPost,
		Path:    "/users",
		Handler: createUserHandler,
	})

	server.AddRoute(rest.Route{
		Method:  http.MethodPut,
		Path:    "/users/:id",
		Handler: updateUserHandler,
	})

	server.AddRoute(rest.Route{
		Method:  http.MethodDelete,
		Path:    "/users/:id",
		Handler: deleteUserHandler,
	})

	// Group routes with prefix
	apiGroup := server.Group("/api/v1")
	apiGroup.AddRoute(rest.Route{
		Method:  http.MethodGet,
		Path:    "/products",
		Handler: getProductsHandler,
	})

	apiGroup.AddRoute(rest.Route{
		Method:  http.MethodPost,
		Path:    "/products",
		Handler: createProductHandler,
	})

	// Alternative method-based routing (if supported)
	server.Get("/health", healthHandler)
	server.Post("/login", loginHandler)
	server.Put("/profile", updateProfileHandler)

	server.Start()
}

func homeHandler(w http.ResponseWriter, r *http.Request) {
	httpx.OkJson(w, map[string]string{"message": "Hello World"})
}

func getUserHandler(w http.ResponseWriter, r *http.Request) {
	id := httpx.ParsePath(r, "id").ToString()
	name := httpx.ParseForm(r, "name").ToString()
	httpx.OkJson(w, map[string]string{"id": id, "name": name})
}

func createUserHandler(w http.ResponseWriter, r *http.Request) {
	email := httpx.ParseHeader(r, "email").ToString()
	httpx.OkJson(w, map[string]string{"email": email})
}

func updateUserHandler(w http.ResponseWriter, r *http.Request) {
	// Handler implementation
}

func deleteUserHandler(w http.ResponseWriter, r *http.Request) {
	// Handler implementation
}

func getProductsHandler(w http.ResponseWriter, r *http.Request) {
	category := httpx.ParseForm(r, "category").ToString()
	httpx.OkJson(w, map[string]string{"category": category})
}

func createProductHandler(w http.ResponseWriter, r *http.Request) {
	// Handler implementation
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	httpx.OkJson(w, map[string]string{"status": "ok"})
}

func loginHandler(w http.ResponseWriter, r *http.Request) {
	username := httpx.ParseForm(r, "username").ToString()
	password := httpx.ParseForm(r, "password").ToString()
	httpx.OkJson(w, map[string]string{"username": username, "password": password})
}

func updateProfileHandler(w http.ResponseWriter, r *http.Request) {
	// Handler implementation
}