// Controller + router wiring. None of the value-getter `.Get(...)`
// calls below (env lookup, request-param read, struct-meta read) are
// routes — they share the `Get` verb name but pass a bare key, never a
// `/`-prefixed path, so the walker must not mint endpoints for them.
package controller

import (
	"context"

	"github.com/gogf/gf/v2/frame/g"
	"github.com/gogf/gf/v2/net/ghttp"
	"github.com/gogf/gf/v2/os/genv"

	v1 "gf_meta/api/user/v1"
)

type cUser struct{}

func Register(s *ghttp.Server) {
	s.Group("/api", func(group *ghttp.RouterGroup) {
		group.Bind(
			&cUser{},
		)
	})
}

func (c *cUser) Get(ctx context.Context, req *v1.GetUserReq) (res *v1.GetUserRes, err error) {
	r := g.RequestFromCtx(ctx)
	_ = genv.Get("GOPATH").String()    // env read, not a route
	_ = r.Get("authorization").String() // request-param read, not a route
	return
}
