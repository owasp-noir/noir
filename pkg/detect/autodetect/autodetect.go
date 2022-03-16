package autodetect

import (
	"io/ioutil"
	"path/filepath"
	"strings"
	"sync"

	"github.com/hahwul/noir/pkg/models"
	"github.com/hahwul/noir/pkg/noir"
)

var (
	Patterns = []models.AutoDetect{}
)

func AutoDetect(files []string) []string {
	var detected []string
	var result map[string]bool
	result = map[string]bool{}
	resultChan := make(chan map[string]bool)
	initRails()
	initSinatra()
	initDjango()
	initEcho()
	initPhp()
	initJsp()
	initSpring()

	go func(rtn chan map[string]bool) {
		for {
			for key, value := range <-rtn {
				result[key] = value
			}
		}
	}(resultChan)

	var wg sync.WaitGroup
	jobs := make(chan string)
	for i := 0; i < noir.FileConcurrency; i++ {
		wg.Add(1)
		go func() {
			for file := range jobs {
				rtn := isDetect(file)
				resultChan <- rtn
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
	for key, _ := range result {
		detected = append(detected, key)
	}
	return detected
}

func isDetect(filename string) map[string]bool {
	var result map[string]bool
	result = map[string]bool{}
	for _, lang := range Patterns {
		for _, pattern := range lang.Patterns {
			if pattern.Ext != "" {
				ext := filepath.Ext(filename)
				if pattern.Ext == ext {
					if pattern.File != "" {
						if filepath.Base(filename) == pattern.File {
							if pattern.Match != "" {
								if matchFile(filename, pattern.Match) {
									result[lang.Name] = true
								}
							} else {
								result[lang.Name] = true
							}
						}
					} else {
						if pattern.Match != "" {
							if matchFile(filename, pattern.Match) {
								result[lang.Name] = true
							}
						} else {
							result[lang.Name] = true
						}
					}
				}
			} else {
				if pattern.Match != "" {
					if matchFile(filename, pattern.Match) {
						result[lang.Name] = true
					}
				} else {
					result[lang.Name] = true
				}
			}
		}
	}
	return result
}

func matchFile(filename, matcher string) bool {
	dat, err := ioutil.ReadFile(filename)
	if err == nil {
		if strings.Contains(string(dat), matcher) {
			return true
		}
	}
	return false
}
