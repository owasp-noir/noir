package attacksurface

import (
	"bufio"
	"os"
	"path/filepath"
	"sync"

	"github.com/hahwul/noir/pkg/models"
	"github.com/hahwul/noir/pkg/noir"
)

func ScanRails(files []string, options models.Options) []models.AttackSurfaceEndpoint {
	const (
		publicDir = "public"
		routes    = "config/routes.rb"
	)
	var result []models.AttackSurfaceEndpoint
	var wg sync.WaitGroup
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
				url := MakeURL(options.BaseHost, GetRealPath(options.BasePath, filename))
				ext := filepath.Ext(filename)
				_ = ext
				_ = url
				if filepath.Dir(GetRealPath(options.BasePath, filename)) == publicDir {
					ppath := GetRealPath(options.BasePath, filename)
					publicUrl := MakeURL(options.BaseHost, ppath[7:len(ppath)])
					obj := models.AttackSurfaceEndpoint{
						Type:        "public",
						URL:         publicUrl,
						Method:      "GET",
						ContentType: "",
						Body:        "",
					}
					fileResult = append(fileResult, obj)
				}
				if GetRealPath(options.BasePath, filename) == routes {
					// TODO Parse routes.rb
				}
				if ext == ".rb" {
					f, err := os.OpenFile(filename, os.O_RDONLY, os.ModePerm)
					if err != nil {

					}
					defer f.Close()

					sc := bufio.NewScanner(f)
					for sc.Scan() {
						line := sc.Text()
						_ = line
					}
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
