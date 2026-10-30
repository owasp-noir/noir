package cmd

import "github.com/spf13/cobra"

var rootCmd = &cobra.Command{Use: "shopscope"}

func Execute() { _ = rootCmd.Execute() }

func init() {
	rootCmd.AddCommand(newOrdersCmd())
}
