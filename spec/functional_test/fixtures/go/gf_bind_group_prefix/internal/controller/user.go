package controller

import (
	"context"

	v1 "example.com/gfbind/api/v1"
)

type Ctrl struct{}

func NewCtrl() *Ctrl { return &Ctrl{} }

func (c *Ctrl) Profile(ctx context.Context, req *v1.ProfileReq) (res *v1.ProfileRes, err error) {
	return
}
