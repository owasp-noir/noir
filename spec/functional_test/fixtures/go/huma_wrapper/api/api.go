package api

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"github.com/danielgtaylor/huma/v2/autopatch"
)

// GroupPrefix is where the router mounts this API.
const GroupPrefix = "/api/v2"

var publicSecurity = []map[string][]string{}

// EnableAutoPatch adds a PATCH to every path with a GET and a PUT.
func EnableAutoPatch(api huma.API) {
	autopatch.AutoPatch(api)
}

func NewAPI(cfg huma.Config) {
	cfg.Servers = []*huma.Server{{URL: GroupPrefix}}
	oapi := cfg.OpenAPI
	oapi.Security = []map[string][]string{
		{"JWTKeyAuth": {}},
		{"APITokenAuth": {}},
	}
}

// Register wraps huma.Register; the Operation literal it is handed is the route.
func Register[I, O any](api huma.API, op huma.Operation, handler func(context.Context, *I) (*O, error)) {
	if op.Method == http.MethodPost {
		op.DefaultStatus = http.StatusCreated
	}
	huma.Register(api, op, handler)
}

type labelReadInput struct {
	ID     int64  `path:"id"`
	Expand string `query:"expand"`
}

type labelOutput struct {
	Body struct {
		Title string `json:"title"`
	}
}

func RegisterLabelRoutes(api huma.API) {
	Register(api, huma.Operation{
		Method: http.MethodGet,
		Path:   "/labels/{id}",
	}, labelsRead)

	Register(api, huma.Operation{
		Method: http.MethodPut,
		Path:   "/labels/{id}",
	}, labelsRead)

	Register(api, huma.Operation{
		Method:   http.MethodPost,
		Path:     "/login",
		Security: publicSecurity,
	}, login)

	Register(api, huma.Operation{
		Method:   http.MethodGet,
		Path:     "/info",
		Security: []map[string][]string{},
	}, info)

	Register(api, huma.Operation{
		Method:   http.MethodGet,
		Path:     "/feed.atom",
		Security: []map[string][]string{{"BasicAuth": {}}},
	}, info)
}

func labelsRead(ctx context.Context, in *labelReadInput) (*labelOutput, error) {
	return nil, nil
}

func login(ctx context.Context, in *struct{}) (*labelOutput, error) {
	return nil, nil
}

func info(ctx context.Context, in *struct{}) (*labelOutput, error) {
	return nil, nil
}
