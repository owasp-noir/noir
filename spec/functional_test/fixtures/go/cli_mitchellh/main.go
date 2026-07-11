package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/mitchellh/cli"
)

type DeployCommand struct{}

func (c *DeployCommand) Run(args []string) int {
	fs := flag.NewFlagSet("deploy", flag.ContinueOnError)
	var target string
	fs.StringVar(&target, "target", "", "deployment target")
	fs.Parse(args)

	token := os.Getenv("MITCHELLH_TOKEN")
	fmt.Println(target, token)
	return 0
}

func (c *DeployCommand) Help() string     { return "deploy the application" }
func (c *DeployCommand) Synopsis() string { return "deploy the app" }

func main() {
	c := cli.NewCLI("mitchellhdemo", "1.0.0")
	c.Commands = map[string]cli.CommandFactory{
		"deploy": func() (cli.Command, error) {
			return &DeployCommand{}, nil
		},
	}

	exitStatus, err := c.Run()
	if err != nil {
		fmt.Println(err)
	}
	os.Exit(exitStatus)
}
