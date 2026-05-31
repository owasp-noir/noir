// Regression fixture: a Huma v2 app registers operations through
// `huma.Register(api, huma.Operation{...}, handler)`. Method and
// Path live verbatim on the Operation literal; Input/Output struct
// fields carry `path`/`query`/`header`/`cookie`/body tags that
// classify the parameters.
package main

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
)

type ListUsersInput struct {
	Limit  int    `query:"limit"`
	Cursor string `query:"cursor"`
	Auth   string `header:"X-Auth"`
}

type ListUsersOutput struct {
	Body []User
}

type GetUserInput struct {
	ID      string `path:"id"`
	Session string `cookie:"session"`
}

type GetUserOutput struct {
	Body User
}

type CreateUserInput struct {
	Body struct {
		Name  string `json:"name"`
		Email string `json:"email"`
	}
}

type CreateUserOutput struct {
	Body User
}

type DeleteUserInput struct {
	ID string `path:"id"`
}

type DeleteUserOutput struct{}

type HealthInput struct {
	Verbose bool `query:"verbose"`
}

type HealthOutput struct{}

type User struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Email string `json:"email"`
}

func registerRoutes(api huma.API) {
	huma.Register(api, huma.Operation{
		OperationID: "list-users",
		Method:      http.MethodGet,
		Path:        "/users",
		Summary:     "List users",
	}, func(ctx context.Context, input *ListUsersInput) (*ListUsersOutput, error) {
		return &ListUsersOutput{}, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-user",
		Method:      http.MethodGet,
		Path:        "/users/{id}",
	}, func(ctx context.Context, input *GetUserInput) (*GetUserOutput, error) {
		return &GetUserOutput{}, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "create-user",
		Method:      http.MethodPost,
		Path:        "/users",
	}, func(ctx context.Context, input *CreateUserInput) (*CreateUserOutput, error) {
		return &CreateUserOutput{}, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "delete-user",
		Method:      "DELETE",
		Path:        "/users/{id}",
	}, func(ctx context.Context, input *DeleteUserInput) (*DeleteUserOutput, error) {
		return &DeleteUserOutput{}, nil
	})

	// Huma v2 typed convenience helpers — the path is the SECOND
	// argument (the first is the API), the verb is the method name.
	huma.Get(api, "/health", func(ctx context.Context, input *HealthInput) (*HealthOutput, error) {
		return &HealthOutput{}, nil
	})

	huma.Patch(api, "/users/{id}", func(ctx context.Context, input *GetUserInput) (*GetUserOutput, error) {
		return &GetUserOutput{}, nil
	})
}

func main() {}
