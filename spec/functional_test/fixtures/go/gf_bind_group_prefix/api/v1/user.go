package v1

import "github.com/gogf/gf/v2/frame/g"

type ProfileReq struct {
	g.Meta `path:"/profile" method:"get"`
}

type ProfileRes struct{}

type UnboundReq struct {
	g.Meta `path:"/unbound" method:"post"`
	Name   string `json:"name"`
}
