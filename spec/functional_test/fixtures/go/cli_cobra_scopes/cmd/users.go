package cmd

import "github.com/spf13/cobra"

var usersCmd = &cobra.Command{Use: "users"}

func init() {
	// Function-local: orders.go has a `get` of its own.
	var get = &cobra.Command{Use: "get"}
	get.Flags().String("user-id", "", "")
	usersCmd.AddCommand(get)
	rootCmd.AddCommand(usersCmd)
}
