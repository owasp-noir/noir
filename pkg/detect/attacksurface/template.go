package attacksurface

import (
	"sync"

	"github.com/hahwul/noir/pkg/models"
	"github.com/hahwul/noir/pkg/noir"
)

func ScanTemplate(files []string, basePath string) []models.AttackSurfaceEndpoint {
	var result []models.AttackSurfaceEndpoint
	var wg sync.WaitGroup
	jobs := make(chan string)
	for i := 0; i < noir.FileConcurrency; i++ {
		wg.Add(1)
		go func() {
			for file := range jobs {
				_ = file
				// Logic
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
