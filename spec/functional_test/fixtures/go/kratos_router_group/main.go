package main

import (
	"github.com/go-kratos/kratos/v2/transport/http"
)

func h(ctx http.Context) error { return nil }

func main() {
	httpSrv := http.NewServer(http.Address(":8000"))
	r := httpSrv.Route("/api")
	r.GET("/hello/{name}", h)
	r2 := r.Group("/v2")
	r2.GET("/say/{name}", h)
	r3 := r2.Group("/admin")
	r3.POST("/reset", h)
}
