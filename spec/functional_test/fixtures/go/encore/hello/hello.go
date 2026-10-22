package hello

import (
	"context"
	"net/http"
)

type Response struct {
	Message string
}

// Hello greets a person by name.
//
//encore:api public method=GET path=/hello/:name
func Hello(ctx context.Context, name string) (*Response, error) {
	return &Response{Message: "Hello, " + name}, nil
}

// Ping has no path or method, so it defaults to /hello.Ping on GET and POST.
//
//encore:api public
func Ping(ctx context.Context) (*Response, error) {
	return &Response{Message: "pong"}, nil
}

//encore:api public raw path=/webhooks/*rest
func Webhook(w http.ResponseWriter, req *http.Request) {
	w.WriteHeader(http.StatusOK)
}

// encore:api public path=/not-a-directive
func NotAnAPI(ctx context.Context) error {
	return nil
}

//encore:api public raw method=GET path=/!fallback
func Frontend(w http.ResponseWriter, req *http.Request) {
	w.WriteHeader(http.StatusNotFound)
}
