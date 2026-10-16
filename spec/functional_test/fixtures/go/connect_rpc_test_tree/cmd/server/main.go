package main

import (
	"net/http"

	"connectrpc.com/connect"
	"github.com/hahwul/test-go-connect-tree/gen/greet/v1/greetv1connect"
)

type greetServer struct{}

var _ = connect.NewResponse[string]

func main() {
	mux := http.NewServeMux()
	path, handler := greetv1connect.NewGreetServiceHandler(&greetServer{})
	mux.Handle(path, handler)
	http.ListenAndServe(":8080", mux)
}
