package attacksurface

import (
	"path/filepath"
	"sync"

	"github.com/hahwul/noir/pkg/models"
	"github.com/hahwul/noir/pkg/noir"
)

const (
	publicDir = "public"
	route     = "config/route.rb"
)

func ScanRails(files []string, basePath string) []models.AttackSurfaceEndpoint {
	var result []models.AttackSurfaceEndpoint
	var wg sync.WaitGroup
	jobs := make(chan string)
	for i := 0; i < noir.FileConcurrency; i++ {
		wg.Add(1)
		go func() {
			for file := range jobs {
				if filepath.Dir(file) == publicDir {

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
