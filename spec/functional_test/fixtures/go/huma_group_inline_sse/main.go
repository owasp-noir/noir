package main

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"github.com/danielgtaylor/huma/v2/adapters/humago"
	"github.com/danielgtaylor/huma/v2/sse"
)

type Out struct{}

type ListInput struct {
	Limit int `query:"limit"`
}

func main() {
	mux := http.NewServeMux()
	api := humago.New(mux, huma.DefaultConfig("x", "1"))

	huma.Register(api, huma.Operation{Method: http.MethodPut, Path: "/count/{count}"},
		func(ctx context.Context, input *struct {
			PathCount  int `path:"count"`
			QueryCount int `query:"q"`
			Hdr        int `header:"X-Count"`
			Body       struct {
				Name string `json:"name"`
			}
		}) (*Out, error) {
			return nil, nil
		})

	v1 := huma.NewGroup(api, "/v1")
	huma.Get(v1, "/items", func(ctx context.Context, input *ListInput) (*Out, error) { return nil, nil })
	admin := huma.NewGroup(v1, "/admin")
	huma.Register(admin, huma.Operation{Method: http.MethodDelete, Path: "/items/{id}"},
		func(ctx context.Context, input *struct {
			ID string `path:"id"`
		}) (*Out, error) {
			return nil, nil
		})

	v2 := huma.NewGroup(api, "/v2", "/api/v2")
	huma.Get(v2, "/ping", func(ctx context.Context, input *struct{}) (*Out, error) { return nil, nil })

	sse.Register(api, huma.Operation{Method: http.MethodGet, Path: "/sse"}, map[string]any{"n": 1},
		func(ctx context.Context, input *struct{}, send sse.Sender) {})

	http.ListenAndServe(":8888", mux)
}
