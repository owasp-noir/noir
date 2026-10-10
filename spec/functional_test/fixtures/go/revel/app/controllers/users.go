package controllers

import "github.com/revel/revel"

type Users struct {
	*revel.Controller
}

func (c Users) Update(id int, name, email string) revel.Result {
	return c.RenderJSON(id)
}

func (c *Users) List(page int) revel.Result {
	return c.RenderJSON(page)
}
