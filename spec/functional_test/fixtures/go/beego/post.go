package main

import beego "github.com/beego/beego/v2/server/web"

// Context getters (`GetString`, `GetInt`, ...) read Request.Form. The
// body is part of Form on POST/PUT/PATCH; on GET and DELETE it is the
// query string. Methods are declared above the Router calls so a missed
// controller-body walk cannot attach them via the line scan.
type PostController struct {
	beego.Controller
}

func (c *PostController) Search() {
	_ = c.GetString("q")
}

func (c *PostController) PostMessage() {
	_ = c.GetString("message")
}

func (c *PostController) PutMessage() {
	_ = c.GetInt("n")
}

func (c *PostController) PatchMessage() {
	_ = c.GetBool("on")
}

func (c *PostController) DeleteMessage() {
	_ = c.GetString("id")
}

func init() {
	beego.Router("/search", &PostController{}, "get:Search")
	beego.Router("/post", &PostController{}, "post:PostMessage")
	beego.Router("/post", &PostController{}, "put:PutMessage")
	beego.Router("/post", &PostController{}, "patch:PatchMessage")
	beego.Router("/post", &PostController{}, "delete:DeleteMessage")
}
