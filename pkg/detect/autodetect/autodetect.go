package autodetect

import "github.com/hahwul/noir/pkg/models"

var (
	Patterns = []models.AutoDetect{}
)

func AutoDetect() {
	_ = Patterns
	initRails()
	initSinatra()
	initDjango()
	initEcho()
}
