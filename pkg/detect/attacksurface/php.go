package attacksurface

import (
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
				ep := models.AttackSurfaceEndpoint{
					URL:         url,
					Method:      "GET",
					ContentType: "form",
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
