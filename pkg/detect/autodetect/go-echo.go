package autodetect

import "github.com/hahwul/noir/pkg/models"

func initEcho() {
	Patterns = append(Patterns, models.AutoDetect{
		Name: "go-echo",
		Patterns: []models.AutoDetectPattern{
			{
				File:  "go.mod",
				Ext:   "mod",
				Match: "github.com/labstack/echo",
			},
		},
	})
}
