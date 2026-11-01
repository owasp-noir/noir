package controllers

import "github.com/beego/beego/v2/server/web"

// BaseController carries actions every controller embedding it serves.
type BaseController struct {
	web.Controller
}

func (c *BaseController) Health() {
	c.Data["json"] = c.Ctx.Input.Query("probe")
}

// UserController declares no Ping; StatusController does.
type UserController struct {
	BaseController
}

type StatusController struct {
	web.Controller
}

func (c *StatusController) Ping() {
	c.Data["json"] = c.Ctx.Input.Query("statusOnly")
}
