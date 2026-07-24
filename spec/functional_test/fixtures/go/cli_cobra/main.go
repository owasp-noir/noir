package main

import (
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var (
	verbose bool
	port    int
)

var rootCmd = &cobra.Command{
	Use:   "cobrademo",
	Short: "A demo cobra CLI",
}

var serveCmd = &cobra.Command{
	Use:   "serve",
	Short: "Start the service",
	Run: func(cmd *cobra.Command, args []string) {
	},
}

// Commented-out registrations are not part of the CLI surface. Pre-fix the
// analyzer matched raw source, so this became a real `migrate` command.
// var migrateCmd = &cobra.Command{
// 	Use:   "migrate",
// 	Short: "Run migrations",
// }

/*
   A block comment is equally not a registration:
   rootCmd.Flags().StringVar(&dead, "block-flag", "", "")
*/

func init() {
	rootCmd.PersistentFlags().BoolVar(&verbose, "verbose", false, "verbose output")
	serveCmd.Flags().IntVar(&port, "port", 8080, "listen port")
	// rootCmd.Flags().StringVar(&secret, "secret-token", "", "never registered")
	viper.BindEnv("api_key", "COBRA_API_KEY")
	rootCmd.AddCommand(serveCmd)
	// rootCmd.AddCommand(migrateCmd)
}

func main() {
	rootCmd.Execute()
}
