package handler

import (
	"net/http"

	"github.com/zeromicro/go-zero/rest"
)

func RegisterHandlers(server *rest.Server) {
	server.AddRoutes(
		[]rest.Route{
			{Method: http.MethodPost, Path: "/run", Handler: RunHandler()},
			{
				Method:  http.MethodPost,
				Path:    "/run2",
				Handler: RunHandler(),
			},
		},
	)
}
