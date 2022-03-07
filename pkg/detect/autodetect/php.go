package autodetect

import "github.com/hahwul/noir/pkg/models"

func initPhp() {
	Patterns = append(Patterns, models.AutoDetect{
		Name: "php",
		Patterns: []models.AutoDetectPattern{
			{
				File:  "",
				Ext:   ".php",
				Match: "",
			},
		},
	})
}
