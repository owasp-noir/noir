package api

import (
	"context"
	"errors"
)

var ErrUnauthenticated = errors.New("authentication required")

type Authorizer struct{ private bool }

type Result struct{ User string }

// CheckAccess lets an authenticated caller through, and an anonymous one
// only to a public procedure.
func (a *Authorizer) CheckAccess(ctx context.Context, procedure string, result *Result) error {
	if result != nil {
		return nil
	}
	if !IsPublicMethod(procedure) {
		return ErrUnauthenticated
	}
	if IsBootstrapMethod(procedure) {
		return nil
	}
	if a.private {
		return ErrUnauthenticated
	}
	return nil
}
