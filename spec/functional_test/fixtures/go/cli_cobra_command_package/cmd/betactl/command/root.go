package command

import (
	"os"

	"github.com/spf13/cobra"
)

func Execute() error {
	var root = &cobra.Command{
		Use: "betactl",
	}
	root.PersistentFlags().String("config", "", "config file")

	var serve = &cobra.Command{
		Use: "serve",
	}
	serve.Flags().Int("beta-port", 8080, "port")

	root.AddCommand(serve)
	_ = os.Getenv("BETA_TOKEN")
	return root.Execute()
}
