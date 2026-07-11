package main

import (
	"fmt"
	"os"

	"github.com/alecthomas/kingpin/v2"
)

var (
	app       = kingpin.New("kingpindemo", "A demo kingpin CLI application.")
	verbose   = app.Flag("verbose", "Enable verbose output.").Bool()
	deployCmd = app.Command("deploy", "Deploy the application.")
	target    = deployCmd.Arg("target", "Deployment target.").String()
	token     = deployCmd.Flag("token", "API token.").Envar("KINGPIN_TOKEN").String()
)

func main() {
	switch kingpin.MustParse(app.Parse(os.Args[1:])) {
	case deployCmd.FullCommand():
		fmt.Println(*target, *token, *verbose)
	}
}
