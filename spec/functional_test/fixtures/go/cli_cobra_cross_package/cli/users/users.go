package users

import "github.com/spf13/cobra"

var Cmd = &cobra.Command{Use: "users"}
var getCmd = &cobra.Command{Use: "get"}

func init() {
	Cmd.AddCommand(getCmd)
	getCmd.Flags().String("user-id", "", "")
}
