package attacksurface

import (
	"github.com/hahwul/noir/pkg/models"
	vLog "github.com/hahwul/volt/logger"
)

func ScanAttackSurface(files, langs []string, options models.Options) []models.AttackSurfaceEndpoint {
	var result []models.AttackSurfaceEndpoint
	logger := vLog.GetLogger(options.Debug)

	for _, lang := range langs {
		switch lang {
		case "rails":
			result = append(result, ScanRails(files, options)...)
		case "php":
			result = append(result, ScanPhp(files, options)...)
		}

	}
	logger.Debug(result)
	return result
}
