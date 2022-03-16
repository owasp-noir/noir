package attacksurface

import "regexp"

type DetectPattern struct {
	Type    string
	Pattern *regexp.Regexp
}
