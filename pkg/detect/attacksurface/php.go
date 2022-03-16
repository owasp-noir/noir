package attacksurface

import (
	"bufio"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"

	"github.com/hahwul/noir/pkg/models"
	"github.com/hahwul/noir/pkg/noir"
	utils "github.com/hahwul/noir/pkg/utils"
	volt "github.com/hahwul/volt/format/har"
)

type DetectPattern struct {
	Type    string
	Pattern *regexp.Regexp
}

func ScanPhp(files []string, options models.Options) []models.AttackSurfaceEndpoint {
	var result []models.AttackSurfaceEndpoint
	var wg sync.WaitGroup
	patterns := []DetectPattern{
		{
			Type:    "GET",
			Pattern: utils.GetRegex("\\$_GET\\[([\\s\\S]*)]"),
		},
		{
			Type:    "POST",
			Pattern: utils.GetRegex("\\$_POST\\[([\\s\\S]*)]"),
		},
		{
			Type:    "POST",
			Pattern: utils.GetRegex("post_var\\(([^)]+)"),
		},
		{
			Type:    "PUT",
			Pattern: utils.GetRegex("\\$_PUT\\[([\\s\\S]*)]"),
		},
		{
			Type:    "DELETE",
			Pattern: utils.GetRegex("\\$_DELETE\\[([\\s\\S]*)]"),
		},
		{
			Type:    "REQUEST",
			Pattern: utils.GetRegex("\\$_REQUEST\\[([\\s\\S]*)]"),
		},
	}

	resultChan := make(chan models.AttackSurfaceEndpoint)
	jobs := make(chan string)

	go func(ch chan models.AttackSurfaceEndpoint) {
		for {
			result = append(result, <-ch)
		}
	}(resultChan)

	for i := 0; i < noir.FileConcurrency; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for filename := range jobs {
				var fileResult []models.AttackSurfaceEndpoint
				url := MakeURL(options.BaseHost, GetRealPath(options.BasePath, filename))
				ext := filepath.Ext(filename)
				contentType := ""
				if strings.Contains(ext, ".php") {
					f, err := os.OpenFile(filename, os.O_RDONLY, os.ModePerm)
					if err != nil {

					}
					defer f.Close()

					sc := bufio.NewScanner(f)
					for sc.Scan() {
						line := sc.Text()
						for _, pattern := range patterns {
							lst := pattern.Pattern.FindString(line)
							if lst != "" {
								lst = strings.ReplaceAll(lst, "\"", "")
								lst = strings.ReplaceAll(lst, "'", "")
								lst = strings.ReplaceAll(lst, "]", "")
								lst = strings.ReplaceAll(lst, ")", "")
								lst = strings.ReplaceAll(lst, "$_GET[", "")
								lst = strings.ReplaceAll(lst, "$_POST[", "")
								lst = strings.ReplaceAll(lst, "post_var(", "")
								lst = strings.ReplaceAll(lst, "$_PUT[", "")
								lst = strings.ReplaceAll(lst, "$_DELETE[", "")
								lst = strings.ReplaceAll(lst, "$_REQUEST[", "")
								obj := models.AttackSurfaceEndpoint{
									Type:   "",
									URL:    url,
									Method: pattern.Type,
									Params: []volt.QueryString{
										{
											Name:  lst,
											Value: "",
										},
									},
									ContentType: contentType,
									Body:        "",
								}
								if pattern.Type != "GET" {
									obj.Body = obj.Params[0].Name + "=" + obj.Params[0].Value
								}

								fileResult = append(fileResult, obj)
								//resultChan <- obj
							}
						}
					}
					if err := sc.Err(); err != nil {

					}
					if len(fileResult) > 1 {
						var methods []string
						for _, r := range fileResult {
							methods = append(methods, r.Method)
						}
						uMethods := MakeSliceUnique(methods)
						for _, m := range uMethods {
							var comboParams []volt.QueryString
							var comboBody string
							for _, r := range fileResult {
								if r.Method == "GET" {
									comboParams = append(comboParams, r.Params...)
								} else {
									comboBody = comboBody + r.Params[0].Name + "=" + r.Params[0].Value + "&"
								}
							}

							comboObj := models.AttackSurfaceEndpoint{
								Type:   "",
								URL:    url,
								Method: m,
								Params: comboParams,
								Body:   comboBody,
							}
							fileResult = append(fileResult, comboObj)
						}
					}
				}
				for _, fr := range fileResult {
					resultChan <- fr
				}
			}
		}()
	}
	for _, file := range files {
		jobs <- file
	}
	close(jobs)
	wg.Wait()
	close(resultChan)
	return result
}
