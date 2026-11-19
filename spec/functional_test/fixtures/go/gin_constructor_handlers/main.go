package main

import (
	"example.com/ginctor/internal/handler"
	"github.com/gin-gonic/gin"
)

type pinger struct{}

func newPinger() *pinger { return &pinger{} }

func (p *pinger) Ping(c *gin.Context) {
	_ = c.Query("ping_q")
}

func main() {
	r := gin.Default()
	userHandler := handler.NewUserHandler()
	orderHandler, err := handler.NewOrderHandler()
	if err != nil {
		panic(err)
	}
	health := newPinger()

	r.GET("/users", userHandler.List)
	r.POST("/users", userHandler.Create)
	r.GET("/orders", orderHandler.List)
	r.GET("/ping", health.Ping)

	s := &Server{engine: r}
	s.routes()
	_ = r.Run()
}
