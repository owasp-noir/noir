package controllers

import "github.com/beego/beego/v2/server/web"

type ApiController struct {
	web.Controller
}

type AdminController struct {
	web.Controller
}

func (c *ApiController) GetUsers() {
	owner := c.Ctx.Input.Query("owner")
	page := c.Input().Get("p")
	token := c.Ctx.Input.Header("X-Api-Token")
	c.Data["json"] = lookupUsers(owner, page, token)
	c.ServeJSON()
}

// Same name on another controller: only the routed type's method counts.
func (c *AdminController) GetUsers() {
	c.Data["json"] = c.Ctx.Input.Query("adminOnly")
}

func (c *ApiController) NotifyPayment() {
	owner := c.Ctx.Input.Param(":owner")
	c.Data["json"] = owner
}

func lookupUsers(owner, page, token string) []string { return nil }
