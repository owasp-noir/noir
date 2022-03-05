package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

// detectCmd represents the detect command
var detectCmd = &cobra.Command{
	Use:   "detect <BASE-PATH>",
	Short: "Detect API and page",
	Long:  `Detect API and web page in the source code`,
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("detect called")
	},
}

func init() {
	rootCmd.AddCommand(detectCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// detectCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// detectCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
