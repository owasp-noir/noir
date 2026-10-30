package cmd

import "github.com/spf13/cobra"

// Constructors: every one names its command `cmd`, and the parent links
// through what each returns.
func newOrdersCmd() *cobra.Command {
	cmd := &cobra.Command{Use: "orders"}
	get := &cobra.Command{Use: "get [id]"}
	get.Flags().String("order-id", "", "")
	cmd.AddCommand(get, newOrdersListCmd(), newOrdersCancelCmd())
	return cmd
}

func newOrdersListCmd() *cobra.Command {
	cmd := &cobra.Command{Use: "list"}
	cmd.Flags().Int("limit", 0, "")
	return cmd
}

func newOrdersCancelCmd() *cobra.Command {
	return &cobra.Command{Use: "cancel"}
}
