package autodetect

import "github.com/hahwul/noir/pkg/models"

func initSinatra() {
	Patterns = append(Patterns, models.AutoDetect{
		Name: "ruby-sinatra",
		Patterns: []models.AutoDetectPattern{
			{
				File:  "",
				Ext:   ".rb",
				Match: "require 'sinatra'",
			},
			{
				File:  "",
				Ext:   ".rb",
				Match: "require \"sinatra\"",
			},
		},
	})
}
