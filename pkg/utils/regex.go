package utils

import "regexp"

func GetRegex(r string) *regexp.Regexp {
	rst, _ := regexp.Compile(r)
	return rst
}
