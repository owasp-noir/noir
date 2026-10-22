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

// AdminCommand is never registered in c.Commands below — adminHelper is a
// standalone helper unrelated to the CLI's command factory map. Its own
// Run() must never be attributed to the deploy command.
type AdminCommand struct{}

func (c *AdminCommand) Run(args []string) int {
	token := os.Getenv("ADMIN_TOKEN")
	fmt.Println("admin", token)
	return 0
}

func (c *AdminCommand) Help() string     { return "admin helper" }
func (c *AdminCommand) Synopsis() string { return "admin" }

func main() {
	c := cli.NewCLI("mitchellhfpdemo", "1.0.0")
	c.Commands = map[string]cli.CommandFactory{
		// The command is built via an intermediate variable (idiomatic Go
		// when the command needs field initialization), not a direct
		// `return &DeployCommand{}, nil`.
		"deploy": func() (cli.Command, error) {
			cmd := &DeployCommand{}
			return cmd, nil
		},
	}

	exitStatus, err := c.Run()
	if err != nil {
		fmt.Println(err)
	}
	os.Exit(exitStatus)
}

// adminHelper is an ordinary function, not a CommandFactory closure — its
// `return &AdminCommand{}, nil` line must not be attributed to any command
// registered above it in the file.
func adminHelper() (cli.Command, error) {
	return &AdminCommand{}, nil
}
