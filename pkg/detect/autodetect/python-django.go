package autodetect

import "github.com/hahwul/noir/pkg/models"

func initDjango() {
	Patterns = append(Patterns, models.AutoDetect{
		Name: "python-django",
		Patterns: []models.AutoDetectPattern{
			{
				File:  "",
				Ext:   "py",
				Match: "from django.'",
			},
		},
	})
}
