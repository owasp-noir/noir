package cmd

import (
	"fmt"

	noir "github.com/hahwul/noir/pkg/noir"
	"github.com/spf13/cobra"
)

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "version of noir",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println(noir.VERSION)
	},
}

func init() {
	rootCmd.AddCommand(versionCmd)
}
