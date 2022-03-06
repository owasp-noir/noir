package autodetect

import "github.com/hahwul/noir/pkg/models"

func initSpring() {
	Patterns = append(Patterns, models.AutoDetect{
		Name: "java-spring",
		Patterns: []models.AutoDetectPattern{
			{
				File:  "pom.xml",
				Ext:   "xml",
				Match: "org.springframework",
			},
		},
	})
}
