package cmd

import (
	"encoding/json"
	"io/ioutil"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/hahwul/noir/pkg/detect/attacksurface"
	"github.com/hahwul/noir/pkg/detect/autodetect"
	export "github.com/hahwul/noir/pkg/export"
	"github.com/hahwul/noir/pkg/models"
	file "github.com/hahwul/volt/file"
	vLog "github.com/hahwul/volt/logger"
	"github.com/spf13/cobra"
)

var output, format, baseHost, basePath string
var ignorePublic, ignoreSwagger bool
var lang, publicPath, ignoreFile, ignoreExt []string

// detectCmd represents the detect command
var detectCmd = &cobra.Command{
	Use:   "detect <BASE-PATH>",
	Short: "Detect API and page",
	Long:  `Detect API and web page in the source code`,
	Run: func(cmd *cobra.Command, args []string) {
		logger := vLog.GetLogger(debug)
		if len(args) < 1 {
			logger.Fatal("The base-path is essential. Please input the value of the first factor.")
		}
		basePath = args[0]
		options := models.Options{
			BasePath: basePath,
			BaseHost: baseHost,
			Debug:    debug,
		}

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
		iLog := eLog.WithField("data2", "ignore")
		if len(ignoreFile) > 0 {
			iLog.Info("ignore predefined files")
		}
		if len(ignoreExt) > 0 {
			iLog.Info("ignore predefined ext of files")
		}
		for index, file := range files {
			eLog.Debug(file)
			_ = index
			for _, ifile := range ignoreFile {
				if filepath.Base(file) == ifile {
					// RemoveIndex()
					// 미리 만들고, 루프 완료 후 큰 값부터 빼면 오류 없을듯
				}
			}
			for _, iext := range ignoreExt {
				if filepath.Ext(file) == iext {
					// RemoveIndex()
					// 미리 만들고, 루프 완료 후 큰 값부터 빼면 오류 없을듯
				}
			}
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
		ase := attacksurface.ScanAttackSurface(files, lang, options)
		if output != "" {
			switch format {
			case "har":
				harData := export.ASEtoHAR(ase)
				fileData, _ := json.MarshalIndent(harData, "", " ")
				_ = ioutil.WriteFile(output, fileData, 0644)
				break
			case "json":
				fileData, _ := json.MarshalIndent(ase, "", " ")
				_ = ioutil.WriteFile(output, fileData, 0644)
				break
			case "curl":
				buf := ""
				for _, endpoint := range ase {
					param := ""
					body := ""
					mime := ""
					if len(endpoint.Params) > 0 {
						param = "?"
						for _, pv := range endpoint.Params {
							param = param + pv.Name + "=" + pv.Value + "&"
						}
					}
					if endpoint.Body != "" {
						body = " -d " + endpoint.Body
					}
					if endpoint.ContentType != "" {
						mime = " -H 'Content-Type: "
						switch endpoint.ContentType {
						case "json":
							mime = mime + "application/json"
							break
						case "form":
							mime = mime + "application/x-www-form-urlencoded"
							break
						}
						mime = mime + "' "
					}
					buf = buf + "curl -i -k " + endpoint.URL + param + body + mime + "\n"
				}
				_ = ioutil.WriteFile(output, []byte(buf), 0644)
				break
			case "plain":
				fileData, _ := json.MarshalIndent(ase, "", " ")
				_ = ioutil.WriteFile(output, fileData, 0644)
				break
			}
			dLog.Info("complete scan")
			logger.Info("finish! found '" + strconv.Itoa(len(ase)) + "' endpoints")
		}
	},
}

func init() {
	rootCmd.AddCommand(detectCmd)
	detectCmd.PersistentFlags().BoolVar(&ignoreSwagger, "ignore-swagger", false, "ignore swagger doc.json")
	detectCmd.PersistentFlags().BoolVar(&ignorePublic, "ignore-public", false, "ignore public/assets directory")
	detectCmd.PersistentFlags().StringVarP(&output, "output", "o", "", "output file")
	detectCmd.PersistentFlags().StringVarP(&format, "output-format", "f", "plain", "output format [plain, json, har]")
	detectCmd.PersistentFlags().StringVar(&baseHost, "base-host", "http://localhost/", "base host")
	detectCmd.PersistentFlags().StringSliceVar(&publicPath, "public-path", []string{}, "set public path")
	detectCmd.PersistentFlags().StringSliceVarP(&lang, "lang", "l", []string{}, "Use fixed language/framework without auto-detection")
	detectCmd.PersistentFlags().StringSliceVar(&ignoreFile, "ignore-file", []string{}, "ignore files")
	detectCmd.PersistentFlags().StringSliceVar(&ignoreExt, "ignore-ext", []string{}, "ignore extensions of file")
}
