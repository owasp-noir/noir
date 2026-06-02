// GoFrame standardized routing: each request struct embeds g.Meta,
// whose tag carries the route (path + method). `group.Bind(controller)`
// wires these up at runtime; the tag itself fully defines the endpoint.
package v1

import "github.com/gogf/gf/v2/frame/g"

// GET with query params (json-tagged + bare field name).
type GetUserReq struct {
	g.Meta `path:"/user/get" method:"get" tags:"User" summary:"get a user"`
	Id     int    `json:"id" dc:"user id"`
	Name   string `json:"name"`
}

type GetUserRes struct{}

// POST -> body params.
type CreateUserReq struct {
	g.Meta   `path:"/user/create" method:"post" tags:"User" summary:"create a user"`
	Username string `json:"username"`
	Email    string `json:"email"`
}

type CreateUserRes struct{}

// Multi-verb method tag fans out to one endpoint per verb.
type UpdateUserReq struct {
	g.Meta `path:"/user/update" method:"put,patch" tags:"User"`
	Id     int `json:"id"`
}

type UpdateUserRes struct{}

// No method tag -> responds to ALL methods (fans out to every verb).
type ListUsersReq struct {
	g.Meta `path:"/user/list" tags:"User" summary:"list users"`
}

type ListUsersRes struct{}
