package cli

import (
	"github.com/spf13/cobra"

	"example.com/shop-tools/cli/users"
)

// The root's Use ("shop") is not the module's basename ("shop-tools").
var rootCmd = &cobra.Command{Use: "shop"}

var ordersCmd = &cobra.Command{Use: "orders [flags]"}
var ordersGet = &cobra.Command{Use: "get [id]"}

func Run() {
	// `users.Cmd` lives in another package; `newHelp()` names no variable.
	rootCmd.AddCommand(ordersCmd, users.Cmd)
	ordersCmd.AddCommand(ordersGet, newHelp())
	ordersGet.Flags().String("order-id", "", "")
	_, _ = rootCmd.ExecuteC()
}

func newHelp() *cobra.Command { return nil }
