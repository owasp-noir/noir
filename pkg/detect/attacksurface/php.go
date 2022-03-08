package attacksurface

import (
	"io/ioutil"
	"path/filepath"
	"strings"
	"sync"

	"github.com/hahwul/noir/pkg/models"
	"github.com/hahwul/noir/pkg/noir"
)

func ScanPhp(files []string, options models.Options) []models.AttackSurfaceEndpoint {
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
				url := MakeURL(options.BaseHost, GetRealPath(options.BasePath, filename))
				ext := filepath.Ext(filename)
				contentType := ""
				method := "GET"
				if strings.Contains(ext, ".php") {
					dat, err := ioutil.ReadFile(filename)
					if err == nil {
						// \$_GET\[".*"]
						// \$_POST\[".*"]
						_ = dat
					}
				}

				ep := models.AttackSurfaceEndpoint{
					URL:         url,
					Method:      method,
					ContentType: contentType,
				}
				resultChan <- ep
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
