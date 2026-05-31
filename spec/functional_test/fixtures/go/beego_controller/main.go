package main

import (
	"github.com/beego/beego/v2/server/web"
)

func main() {
	ctrl := &UserController{}

	// Mapping-less registration: Beego routes each HTTP-verb-named method
	// the controller implements. UserController defines Get + Post.
	web.Router("/users", ctrl)

	// Explicit single-method mappings.
	web.Router("/users/profile", ctrl, "get:Profile")
	web.Router("/users/update", ctrl, "post:Update")

	// Multiple methods sharing one controller method.
	web.Router("/users/batch", ctrl, "get,post:Batch")

	web.Run()
}

// UserController must satisfy Beego's ControllerInterface.
type UserController struct {
	web.Controller
}

func (c *UserController) Get() {
	c.Ctx.Output.Body([]byte("list"))
}

func (c *UserController) Post() {
	c.Ctx.Output.Body([]byte("create"))
}

func (c *UserController) Profile() {
	c.Ctx.Output.Body([]byte("profile"))
}

func (c *UserController) Update() {
	c.Ctx.Output.Body([]byte("update"))
}

func (c *UserController) Batch() {
	c.Ctx.Output.Body([]byte("batch"))
}
