package cmd

import "github.com/spf13/cobra"

// A brace inside a raw string is not a block: `usersLsCmd` below stays
// package-level, so users_sub.go can add it.
var usersCmd = &cobra.Command{
	Use:  "users",
	Long: `Example JSON: {"id": 1`,
}

var usersLsCmd = &cobra.Command{Use: "ls"}

func init() {
	// Function-local: orders.go has a `get` of its own.
	var get = &cobra.Command{Use: "get"}
	get.Flags().String("user-id", "", "")
	usersCmd.AddCommand(get)
	rootCmd.AddCommand(usersCmd)
}
