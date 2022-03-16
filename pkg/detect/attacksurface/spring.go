package attacksurface

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/hahwul/noir/pkg/models"
	"github.com/hahwul/noir/pkg/noir"
	utils "github.com/hahwul/noir/pkg/utils"
	volt "github.com/hahwul/volt/format/har"
)

func ScanSpring(files []string, options models.Options) []models.AttackSurfaceEndpoint {
	const (
		publicDir = "src/main/resources/static"
	)
	var result []models.AttackSurfaceEndpoint
	var wg sync.WaitGroup
	patterns := []DetectPattern{
		{
			Type:    "GET",
			Pattern: utils.GetRegex("@GetMapping([\\S]*)"),
		},
		{
			Type:    "POST",
			Pattern: utils.GetRegex("@PostMapping([\\S]*)"),
		},
		{
			Type:    "PUT",
			Pattern: utils.GetRegex("@PutMapping([\\S]*)"),
		},
		{
			Type:    "DELETE",
			Pattern: utils.GetRegex("@DeleteMapping([\\S]*)"),
		},
		{
			Type:    "REQUEST",
			Pattern: utils.GetRegex("@RequestMapping([\\S]*)"),
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
				var fileResult []models.AttackSurfaceEndpoint
				ext := filepath.Ext(filename)

				if strings.Contains(GetRealPath(options.BasePath, filename), publicDir) {
					ppath := GetRealPath(options.BasePath, filename)
					publicUrl := MakeURL(options.BaseHost, ppath[len(publicDir):len(ppath)])
					obj := models.AttackSurfaceEndpoint{
						Type:        "public",
						URL:         publicUrl,
						Method:      "GET",
						ContentType: "",
						Body:        "",
					}
					fileResult = append(fileResult, obj)
				}
				if ext == ".java" {
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
								lst = strings.ReplaceAll(lst, ")", "")
								lst = strings.ReplaceAll(lst, "@GetMapping(", "")
								lst = strings.ReplaceAll(lst, "@PostMapping(", "")
								lst = strings.ReplaceAll(lst, "@PutMapping(", "")
								lst = strings.ReplaceAll(lst, "@DeleteMapping(", "")
								lst = strings.ReplaceAll(lst, "@RequestMapping(", "")
								springUrl := MakeURL(options.BaseHost, lst)
								obj := models.AttackSurfaceEndpoint{
									Type:   "spring",
									URL:    springUrl,
									Method: pattern.Type,
									Params: []volt.QueryString{
										{
											Name:  lst,
											Value: "",
										},
									},
									ContentType: "",
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
				}
				if GetRealPath(options.BasePath, filename) == "" {
					// TODO
				}
				for _, fr := range fileResult {
					resultChan <- fr
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

	return result
}
