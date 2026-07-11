package main

import (
	"fmt"

	"github.com/alecthomas/kong"
	"github.com/kelseyhightower/envconfig"
)

var CLI struct {
	Verbose bool     `help:"Enable verbose logging." short:"v"`
	Serve   ServeCmd `cmd:"" help:"Start the server."`
}

type ServeCmd struct {
	Host  string `arg:"" help:"Host to bind."`
	Port  int    `help:"Port to listen on." default:"8080"`
	Token string `help:"API token." env:"KONG_API_TOKEN"`
}

// ClientConfig is parsed by envconfig, not kong — it just happens to share
// kong's common struct-tag keys (env/default). It must never be merged
// onto the kong CLI's root command.
type ClientConfig struct {
	Timeout int `env:"HTTP_TIMEOUT" default:"30"`
}

func main() {
	ctx := kong.Parse(&CLI)

	var cfg ClientConfig
	envconfig.Process("client", &cfg)

	switch ctx.Command() {
	case "serve <host>":
		fmt.Println("serving", cfg.Timeout)
	}
}
