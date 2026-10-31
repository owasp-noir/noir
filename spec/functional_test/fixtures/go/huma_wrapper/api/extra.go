package api

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
)

type itemInput struct {
	ID int64 `path:"id"`
}

func item(ctx context.Context, in *itemInput) (*labelOutput, error) {
	return nil, nil
}

// An inline input struct: its path, query and body fields are the params.
func itemUpdate(ctx context.Context, in *struct {
	ID     int64  `path:"id"`
	Format string `query:"format"`
	Body   struct {
		Title string `json:"title"`
	}
}) (*labelOutput, error) {
	return nil, nil
}

func describe(name string, op huma.Operation) {}

// A wrapper that opts the operations it registers out of the default.
func registerPublic[I, O any](api huma.API, op huma.Operation, handler func(context.Context, *I) (*O, error)) {
	op.Security = []map[string][]string{}
	huma.Register(api, op, handler)
}

// A wrapper of the wrapper: it hands the operation on to `Register`.
func registerGated[I, O any](api huma.API, op huma.Operation, handler func(context.Context, *I) (*O, error)) {
	Register(api, op, handler)
}

func RegisterExtraRoutes(api huma.API) {
	// A docs helper taking an Operation literal is not a registration.
	describe("x", huma.Operation{Method: http.MethodGet, Path: "/not-a-route"})

	registerGated(api, huma.Operation{Method: http.MethodGet, Path: "/gated"}, item)

	registerPublic(api, huma.Operation{Method: http.MethodPost, Path: "/signup"}, item)

	// A modifier that only fills in a missing security, and a group made
	// from a group whose modifier makes it public.
	filled := huma.NewGroup(api, "/filled")
	filled.UseModifier(func(op *huma.Operation, next func(*huma.Operation)) {
		if op.Security == nil {
			op.Security = []map[string][]string{{"AdminKey": {}}}
		}
		next(op)
	})
	huma.Register(filled, huma.Operation{Method: http.MethodGet, Path: "/own", Security: []map[string][]string{}}, item)
	huma.Register(filled, huma.Operation{Method: http.MethodGet, Path: "/unset"}, item)
	open := huma.NewGroup(api, "/open")
	open.UseModifier(func(op *huma.Operation, next func(*huma.Operation)) {
		op.Security = []map[string][]string{}
		next(op)
	})
	sub := huma.NewGroup(open, "/sub")
	huma.Register(sub, huma.Operation{Method: http.MethodGet, Path: "/x"}, item)

	// A sugar call whose operation modifier opts it out of the default.
	huma.Get(api, "/health", info, func(o *huma.Operation) {
		o.Security = []map[string][]string{}
	})

	// A group under the server base path, its modifier setting security.
	admin := huma.NewGroup(api, "/admin")
	admin.UseModifier(func(op *huma.Operation, next func(*huma.Operation)) {
		op.Security = []map[string][]string{{"AdminKey": {}}}
		next(op)
	})
	huma.Register(admin, huma.Operation{Method: http.MethodDelete, Path: "/users/{id}"}, item)

	// GET and PUT with an object body: AutoPatch adds a PATCH...
	huma.Register(api, huma.Operation{Method: http.MethodGet, Path: "/items/{id}"}, item)
	huma.Register(api, huma.Operation{Method: http.MethodPut, Path: "/items/{id}"}, itemUpdate)

	// ...but not when the metadata turns it off, or the PUT has no body.
	huma.Register(api, huma.Operation{Method: http.MethodGet, Path: "/nopatch/{id}", Metadata: map[string]any{"autopatch": false}}, item)
	huma.Register(api, huma.Operation{Method: http.MethodPut, Path: "/nopatch/{id}"}, itemUpdate)
	huma.Register(api, huma.Operation{Method: http.MethodGet, Path: "/nobody/{id}"}, item)
	huma.Register(api, huma.Operation{Method: http.MethodPut, Path: "/nobody/{id}"}, item)
}
