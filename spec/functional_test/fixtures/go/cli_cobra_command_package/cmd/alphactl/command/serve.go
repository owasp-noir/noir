package command

import "github.com/spf13/cobra"

// The parent (`rootCmd`) is declared in root.go: one package, one namespace.
var serveCmd = &cobra.Command{
	Use: "serve",
}

var serveStatusCmd = &cobra.Command{
	Use: "status",
}

func init() {
	serveCmd.Flags().Int("alpha-port", 8080, "port")
	serveStatusCmd.Flags().Bool("json", false, "json output")
	serveCmd.AddCommand(serveStatusCmd)
	rootCmd.AddCommand(serveCmd)
}
