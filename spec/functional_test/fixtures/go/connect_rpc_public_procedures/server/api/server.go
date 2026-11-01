package api

import (
	"context"
	"net/http"

	"connectrpc.com/connect"
	"example.com/notes/proto/gen/api/apiconnect"
)

type AuthInterceptor struct{ authorizer *Authorizer }

func (in *AuthInterceptor) WrapUnary(next connect.UnaryFunc) connect.UnaryFunc {
	return func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
		if err := in.authorizer.CheckAccess(ctx, req.Spec().Procedure, nil); err != nil {
			return nil, connect.NewError(connect.CodeUnauthenticated, err)
		}
		return next(ctx, req)
	}
}

type Service struct{}

func NewHandler(s *Service) http.Handler {
	mux := http.NewServeMux()
	interceptors := connect.WithInterceptors(&AuthInterceptor{authorizer: &Authorizer{}})
	mux.Handle(apiconnect.NewAuthServiceHandler(s, interceptors))
	mux.Handle(apiconnect.NewNoteServiceHandler(s, interceptors))
	return mux
}
