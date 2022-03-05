package cmd

import (
	volt "github.com/hahwul/volt/logger"
	"github.com/spf13/cobra"
)

var output, format, baseHost, basePath string
var ignorePublic, ignoreSwagger bool

// detectCmd represents the detect command
var detectCmd = &cobra.Command{
	Use:   "detect <BASE-PATH>",
	Short: "Detect API and page",
	Long:  `Detect API and web page in the source code`,
	Run: func(cmd *cobra.Command, args []string) {
		logger := volt.GetLogger(debug)
		logger.Info("start detect mode")
	},
}

func init() {
	rootCmd.AddCommand(detectCmd)
	detectCmd.PersistentFlags().BoolVar(&ignoreSwagger, "ignore-swagger", false, "ignore swagger doc.json")
	detectCmd.PersistentFlags().BoolVar(&ignorePublic, "ignore-public", false, "ignore public/assets directory")
	detectCmd.PersistentFlags().StringVarP(&output, "output", "o", "", "output file")
	detectCmd.PersistentFlags().StringVarP(&format, "format", "f", "plain", "output format [plain, json, curl]")
	detectCmd.PersistentFlags().StringVar(&baseHost, "base-host", "http://localhost:80", "base host")
	detectCmd.PersistentFlags().StringVar(&basePath, "base-path", "/", "base path")

}
