package main

import (
	"log"

	"github.com/go-kratos/kratos/v2"
	"github.com/go-kratos/kratos/v2/transport/http"

	greeterv1 "github.com/hahwul/test-go-kratos/api/greeter/v1"
	todov1 "github.com/hahwul/test-go-kratos/api/todo/v1"
	"github.com/hahwul/test-go-kratos/internal/service"
)

func main() {
	httpSrv := http.NewServer(http.Address(":8000"))

	todov1.RegisterTodoServiceHTTPServer(httpSrv, service.NewTodoService())
	greeterv1.RegisterGreeterHTTPServer(httpSrv, service.NewGreeterService())

	app := kratos.New(
		kratos.Name("test-go-kratos"),
		kratos.Server(httpSrv),
	)

	if err := app.Run(); err != nil {
		log.Fatal(err)
	}
}
