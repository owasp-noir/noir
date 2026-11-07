package main

import (
	"example.com/echofactory/handler"
	"example.com/echofactory/router"
)

func main() {
	r := router.New()
	v1 := r.Group("/api")
	h := handler.NewHandler()
	h.Register(v1)
	handler.NewHTTP(h, v1)
}
