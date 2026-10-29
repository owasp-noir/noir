package handler

import (
	"net/http"

	"github.com/zeromicro/go-zero/rest"
)

type ServiceContext struct {
	AdminCheck rest.Middleware
	Config     struct{ JwtAuth struct{ AccessSecret string } }
}

func RegisterHandlers(server *rest.Server, serverCtx *ServiceContext) {
	server.AddRoutes(
		rest.WithMiddlewares(
			[]rest.Middleware{serverCtx.AdminCheck},
			[]rest.Route{
				{Method: http.MethodGet, Path: "/users/:id", Handler: DetailHandler(serverCtx)},
				{Method: http.MethodPut, Path: "/users/:id", Handler: UpdateHandler(serverCtx)},
			}...,
		),
		rest.WithJwt(serverCtx.Config.JwtAuth.AccessSecret),
		rest.WithPrefix("/api/v1"),
	)
}
