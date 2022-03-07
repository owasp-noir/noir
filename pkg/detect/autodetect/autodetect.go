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

func AutoDetect(files []string) []models.AutoDetectResult {
	var detected []models.AutoDetectResult
	var result map[string]string
	result = map[string]string{}
	initRails()
	initSinatra()
	initDjango()
	initEcho()
	initPhp()
	initJsp()
	initSpring()

	var wg sync.WaitGroup
	jobs := make(chan string)
	for i := 0; i < noir.FileConcurrency; i++ {
		wg.Add(1)
		go func() {
			for file := range jobs {
				rtn := isDetect(file)
				for key, value := range rtn {
					result[key] = value
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
	for key, _ := range result {
		obj := models.AutoDetectResult{
			Name:     key,
			BasePath: "",
		}
		detected = append(detected, obj)
	}
	return detected
}

func isDetect(filename string) map[string]string {
	var result map[string]string
	result = map[string]string{}
	for _, lang := range Patterns {
		for _, pattern := range lang.Patterns {
			basepath := filepath.Dir(filename)
			if pattern.Ext != "" {
				ext := filepath.Ext(filename)
				if pattern.Ext == ext {
					if pattern.File != "" {
						if filepath.Base(filename) == pattern.File {
							if pattern.Match != "" {
								if matchFile(filename, pattern.Match) {
									result[lang.Name] = basepath
								}
							} else {
								result[lang.Name] = basepath
							}
						}
					} else {
						if pattern.Match != "" {
							if matchFile(filename, pattern.Match) {
								result[lang.Name] = ""
							}
						} else {
							result[lang.Name] = ""
						}
					}
				}
			} else {
				if pattern.Match != "" {
					if matchFile(filename, pattern.Match) {
						result[lang.Name] = ""
					}
				} else {
					result[lang.Name] = ""
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
