package cmd

import (
	"strconv"
	"strings"

	"github.com/hahwul/noir/pkg/detect/autodetect"
	file "github.com/hahwul/volt/file"
	vLog "github.com/hahwul/volt/logger"
	"github.com/spf13/cobra"
)

var output, format, baseHost, basePath string
var ignorePublic, ignoreSwagger bool
var lang, publicPath []string

// detectCmd represents the detect command
var detectCmd = &cobra.Command{
	Use:   "detect <BASE-PATH>",
	Short: "Detect API and page",
	Long:  `Detect API and web page in the source code`,
	Run: func(cmd *cobra.Command, args []string) {
		basePath = args[0]
		logger := vLog.GetLogger(debug)
		logger.Info("start detect mode")
		aLog := logger.WithField("data1", "arguments")
		aLog.Info("baseHost: " + baseHost)
		if len(lang) > 0 {
			aLog.Info("lang: " + strings.Join(lang, " "))
		}
		aLog.Debug("arguments - output: " + output)
		aLog.Debug("arguments - format: " + format)
		files, err := file.GetFiles(args[0])
		if err != nil {
			logger.Fatal(err)
		}
		eLog := logger.WithField("data1", "enum")
		eLog.Info("found " + strconv.Itoa(len(files)) + " files in base directory")
		for _, file := range files {
			eLog.Debug(file)
		}
		dLog := logger.WithField("data1", "detector")
		if len(lang) == 0 {
			dLog.Info("run auto-detection.")
			aLog := dLog.WithField("data2", "auto-detect")
			aLog.Debug("run auto-detection")
			detected := autodetect.AutoDetect(files)
			for _, lv := range detected {
				lang = append(lang, lv)
			}
			aLog.Info(lang)
		}
		sLog := dLog.WithField("data2", strings.Join(lang, " "))
		sLog.Info("start scan attack-surface")
	},
}

func init() {
	rootCmd.AddCommand(detectCmd)
	detectCmd.PersistentFlags().BoolVar(&ignoreSwagger, "ignore-swagger", false, "ignore swagger doc.json")
	detectCmd.PersistentFlags().BoolVar(&ignorePublic, "ignore-public", false, "ignore public/assets directory")
	detectCmd.PersistentFlags().StringVarP(&output, "output", "o", "", "output file")
	detectCmd.PersistentFlags().StringVarP(&format, "format", "f", "plain", "output format [plain, json, curl]")
	detectCmd.PersistentFlags().StringVar(&baseHost, "base-host", "http://localhost:80", "base host")
	detectCmd.PersistentFlags().StringSliceVar(&publicPath, "public-path", []string{}, "set public path")
	detectCmd.PersistentFlags().StringSliceVarP(&lang, "lang", "l", []string{}, "Use fixed language/framework without auto-detection.")
}
