package main

import (
	"github.com/labstack/echo/v4"

	"example.com/echobuilder/handler"
)

func main() {
	e := echo.New()
	v1 := e.Group("/api")
	h := handler.NewHandler()
	h.Register(v1)
	admin := e.Group("/admin")
	handler.RegisterAdmin(h, admin)
	adm := &handler.Admin{}
	adm.Mount(e.Group("/adm"))
	bil := &handler.Billing{}
	bil.Mount(e.Group("/bil"))
	e.Start(":8080")
}
