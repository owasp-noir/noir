package cmd

import "github.com/spf13/cobra"

// Two receiver types, one method name: each `Command()` is its own
// constructor, picked by the type of the variable it is called on.
type usersArchive struct{}

func (u *usersArchive) Command() *cobra.Command {
	cmd := &cobra.Command{Use: "archive"}
	cmd.Flags().String("user-filter", "", "")
	return cmd
}

type ordersArchive struct{}

func (o *ordersArchive) Command() *cobra.Command {
	cmd := &cobra.Command{Use: "archive"}
	cmd.Flags().String("order-filter", "", "")
	return cmd
}

func init() {
	ua := &usersArchive{}
	usersCmd.AddCommand(ua.Command())
}
