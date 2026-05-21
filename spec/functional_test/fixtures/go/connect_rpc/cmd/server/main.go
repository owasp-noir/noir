package main

import (
	"context"
	"net/http"

	"connectrpc.com/connect"
	userv1 "github.com/hahwul/test-go-connect/gen/user/v1"
	"github.com/hahwul/test-go-connect/gen/user/v1/userv1connect"
)

type userServer struct{}

func (s *userServer) GetUser(
	ctx context.Context,
	req *connect.Request[userv1.GetUserRequest],
) (*connect.Response[userv1.GetUserResponse], error) {
	return connect.NewResponse(&userv1.GetUserResponse{
		UserId: req.Msg.UserId,
		Name:   "Alice",
	}), nil
}

func (s *userServer) CreateUser(
	ctx context.Context,
	req *connect.Request[userv1.CreateUserRequest],
) (*connect.Response[userv1.CreateUserResponse], error) {
	return connect.NewResponse(&userv1.CreateUserResponse{
		UserId: "u-1",
	}), nil
}

func (s *userServer) ListUsers(
	ctx context.Context,
	req *connect.Request[userv1.ListUsersRequest],
) (*connect.Response[userv1.ListUsersResponse], error) {
	return connect.NewResponse(&userv1.ListUsersResponse{}), nil
}

func (s *userServer) StreamUsers(
	ctx context.Context,
	req *connect.Request[userv1.ListUsersRequest],
	stream *connect.ServerStream[userv1.GetUserResponse],
) error {
	return nil
}

func main() {
	mux := http.NewServeMux()
	path, handler := userv1connect.NewUserServiceHandler(&userServer{})
	mux.Handle(path, handler)
	http.ListenAndServe(":8080", mux)
}
