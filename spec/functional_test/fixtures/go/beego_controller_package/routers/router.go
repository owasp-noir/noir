package routers

import (
	"github.com/beego/beego/v2/server/web"

	"example.com/idp/controllers"
)

type LocalController struct {
	web.Controller
}

func (c *LocalController) Ping() {
	c.Ctx.Output.Body([]byte(c.Ctx.Input.Query("echo")))
}

func init() {
	web.Router("/api/get-users", &controllers.ApiController{}, "GET:GetUsers")
	web.Router("/api/admin/users", &controllers.AdminController{}, "GET:GetUsers")
	web.Router("/api/notify-payment/?:owner/?:payment", &controllers.ApiController{}, "POST:NotifyPayment")
	web.Router("/api/missing", &controllers.ApiController{}, "GET:NoSuchMethod")
	web.Router("/ping", &LocalController{}, "GET:Ping")
}
