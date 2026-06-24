package main

import "github.com/spf13/cobra"

var verbose bool

// Root command with NO Use: field (only Short/Run) — a common pattern. Its
// flags must attribute to the root cli://<binary>, and it must not borrow the
// serve subcommand's Use: token.
var rootCmd = &cobra.Command{
	Short: "rootless demo",
	Run: func(cmd *cobra.Command, args []string) {
	},
}

var serveCmd = &cobra.Command{
	Use: "serve",
	Run: func(cmd *cobra.Command, args []string) {
	},
}

func init() {
	rootCmd.PersistentFlags().BoolVar(&verbose, "verbose", false, "verbose output")
	rootCmd.AddCommand(serveCmd)
}

func main() {
	rootCmd.Execute()
}
