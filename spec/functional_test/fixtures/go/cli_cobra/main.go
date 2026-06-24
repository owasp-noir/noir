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

func init() {
	rootCmd.PersistentFlags().BoolVar(&verbose, "verbose", false, "verbose output")
	serveCmd.Flags().IntVar(&port, "port", 8080, "listen port")
	viper.BindEnv("api_key", "COBRA_API_KEY")
	rootCmd.AddCommand(serveCmd)
}

func main() {
	rootCmd.Execute()
}
