// Package service implements the business logic behind the generated
// TodoServiceHTTPServer / GreeterHTTPServer interfaces. It intentionally
// does not import "github.com/go-kratos/kratos/v2/transport/http" — the
// Kratos analyzer must not treat this file as a route source, since it
// carries no HTTP route registrations of its own (verifies analyzer
// project scoping).
package service

import (
	"context"

	greeterv1 "github.com/hahwul/test-go-kratos/api/greeter/v1"
	todov1 "github.com/hahwul/test-go-kratos/api/todo/v1"
)

type TodoService struct{}

func NewTodoService() *TodoService {
	return &TodoService{}
}

func (s *TodoService) CreateTodo(ctx context.Context, req *todov1.CreateTodoRequest) (*todov1.Todo, error) {
	return &todov1.Todo{}, nil
}

func (s *TodoService) GetTodo(ctx context.Context, req *todov1.GetTodoRequest) (*todov1.Todo, error) {
	return &todov1.Todo{}, nil
}

func (s *TodoService) UpdateTodo(ctx context.Context, req *todov1.UpdateTodoRequest) (*todov1.Todo, error) {
	return &todov1.Todo{}, nil
}

func (s *TodoService) DeleteTodo(ctx context.Context, req *todov1.DeleteTodoRequest) (*todov1.Todo, error) {
	return &todov1.Todo{}, nil
}

type GreeterService struct{}

func NewGreeterService() *GreeterService {
	return &GreeterService{}
}

func (s *GreeterService) SayHello(ctx context.Context, req *greeterv1.HelloRequest) (*greeterv1.HelloReply, error) {
	return &greeterv1.HelloReply{Message: "Hello " + req.Name}, nil
}
