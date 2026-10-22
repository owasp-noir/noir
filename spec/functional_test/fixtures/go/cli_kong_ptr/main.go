package main

import (
	"fmt"

	"github.com/alecthomas/kong"
)

var CLI struct {
	Verbose bool      `help:"Enable verbose logging." short:"v"`
	Serve   *ServeCmd `cmd:"" help:"Start the server."`
}

type ServeCmd struct {
	Host  string `arg:"" help:"Host to bind."`
	Port  int    `help:"Port to listen on." default:"8080"`
	Token string `help:"API token." env:"KONG_API_TOKEN"`
}

func main() {
	ctx := kong.Parse(&CLI)
	switch ctx.Command() {
	case "serve <host>":
		fmt.Println("serving")
	}
}
