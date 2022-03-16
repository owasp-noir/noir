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
	"github.com/hahwul/noir/pkg/utils"
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
			Pattern: utils.GetRegex("\\$GET\\[([\\s\\S]*)]"),
		},
		{
			Type:    "POST",
			Pattern: utils.GetRegex("\\$POST\\[([\\s\\S]*)]"),
		},
		{
			Type:    "PUT",
			Pattern: utils.GetRegex("\\$PUT\\[([\\s\\S]*)]"),
		},
		{
			Type:    "DELETE",
			Pattern: utils.GetRegex("\\$DELETE\\[([\\s\\S]*)]"),
		},
		{
			Type:    "REQUEST",
			Pattern: utils.GetRegex("\\$REQUEST\\[([\\s\\S]*)]"),
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
			for filename := range jobs {
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
								lst = strings.ReplaceAll(lst, "$GET[", "")
								lst = strings.ReplaceAll(lst, "$POST[", "")
								lst = strings.ReplaceAll(lst, "$PUT[", "")
								lst = strings.ReplaceAll(lst, "$DELETE[", "")
								lst = strings.ReplaceAll(lst, "$REQUEST[", "")
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
								result = append(result, obj)
								//resultChan <- obj
							}
						}
					}
					if err := sc.Err(); err != nil {

					}
				}
			}
			wg.Done()
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
