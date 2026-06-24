package main

import (
	"os"

	"github.com/urfave/cli/v2"
)

func main() {
	app := &cli.App{
		Name: "urfavedemo",
		Flags: []cli.Flag{
			&cli.StringFlag{
				Name:    "config",
				EnvVars: []string{"URFAVE_CONFIG"},
			},
		},
		Commands: []*cli.Command{
			{
				Name: "deploy",
				Flags: []cli.Flag{
					&cli.StringFlag{Name: "target"},
				},
				Action: func(c *cli.Context) error {
					return nil
				},
			},
		},
	}

	app.Run(os.Args)
}
