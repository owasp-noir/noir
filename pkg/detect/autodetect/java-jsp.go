package autodetect

import "github.com/hahwul/noir/pkg/models"

func initJsp() {
	Patterns = append(Patterns, models.AutoDetect{
		Name: "jsp",
		Patterns: []models.AutoDetectPattern{
			{
				File:  "",
				Ext:   "jsp",
				Match: "",
			},
		},
	})
}
