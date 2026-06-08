package main

import (
	"connectrpc.com/connect"
	userv1connect "example.com/service-a/gen/user/v1/userv1connect"
)

type userServer struct{}

func main() {
	userv1connect.NewUserServiceHandler(&userServer{})
	_ = connect.WithInterceptors
}
