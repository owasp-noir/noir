package cmd

import (
	"fmt"
	"os"

	file "github.com/hahwul/volt/file"
	vLog "github.com/hahwul/volt/logger"
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
		logger := vLog.GetLogger(debug)
		logger.Info("start detect mode")
		logger.Info("arguments - baseHost: " + baseHost)
		logger.Info("arguments - basePath: " + basePath)
		logger.Debug("arguments - output: " + output)
		logger.Debug("arguments - format: " + format)
		files, err := file.GetFiles(args[0])
		if err != nil {
			logger.Fatal(err)
		}
		for _, file := range files {
			logger.Debug(file)
		}
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

func readDir(path string) ([]string, error) {
	var fileList []string
	file, err := os.Open(path)
	if err != nil {
		return fileList, err
	}
	defer file.Close()
	names, _ := file.Readdirnames(0)
	for _, name := range names {
		filePath := fmt.Sprintf("%v/%v", path, name)
		file, err := os.Open(filePath)
		if err != nil {
			return fileList, err
		}
		defer file.Close()
		fileInfo, err := file.Stat()
		if err != nil {
			return fileList, err
		}
		fileList = append(fileList, filePath)
		if fileInfo.IsDir() {
			readDir(filePath)
		}
	}
	return fileList, nil
}
