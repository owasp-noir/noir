package command

import (
	"os"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "alphactl",
	Short: "alpha tool",
}

func init() {
	rootCmd.PersistentFlags().String("config", "", "config file")
}

func Execute() error {
	_ = os.Getenv("ALPHA_TOKEN")
	return rootCmd.Execute()
}
