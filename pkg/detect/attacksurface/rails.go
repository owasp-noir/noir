package attacksurface

import (
	"path/filepath"
	"sync"

	"github.com/hahwul/noir/pkg/models"
	"github.com/hahwul/noir/pkg/noir"
)

const (
	publicDir = "public"
	routes    = "config/routes.rb"
)

func ScanRails(files []string, options models.Options) []models.AttackSurfaceEndpoint {
	var result []models.AttackSurfaceEndpoint
	var wg sync.WaitGroup
	jobs := make(chan string)
	for i := 0; i < noir.FileConcurrency; i++ {
		wg.Add(1)
		go func() {
			for filename := range jobs {
				if filepath.Dir(filename) == publicDir {
					//TODO Parse public
				}
				if filename == routes {
					//TODO Parse routes.rb
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
