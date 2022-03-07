package attacksurface

import "github.com/hahwul/noir/pkg/models"

func ScanAttackSurface(baseHost, basePath string, files, langs []string) []models.AttackSurfaceEndpoint {
	var result []models.AttackSurfaceEndpoint

	for _, lang := range langs {
		switch lang {
		case "rails":
			result = append(result, ScanRails(files, basePath)...)
		}
	}

	return result
}
