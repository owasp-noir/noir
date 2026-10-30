package cmd

import "github.com/spf13/cobra"

func init() {
	usersCmd.AddCommand(usersLsCmd, usersExportCmd)
	usersLsCmd.Flags().Int("limit", 0, "")
	usersExportCmd.Flags().String("format", "", "")
}
