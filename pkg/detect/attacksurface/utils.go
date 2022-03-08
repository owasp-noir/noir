package attacksurface

import "strings"

func GetRealPath(basePath, filename string) string {
	var realPath string
	if basePath != "." {
		if string(basePath[0:2]) == "./" {
			tPath := strings.ReplaceAll(basePath, "./", "")
			realPath = strings.ReplaceAll(filename, tPath, "")
		} else {
			realPath = strings.ReplaceAll(filename, basePath, "")
		}
	} else {
		realPath = filename
	}
	return realPath
}

func MakeURL(baseHost, filename string) string {
	lastBaseHostChar := string(baseHost[len(baseHost)-1:])
	firstFilenameChar := string(filename[0:1])
	if lastBaseHostChar == "/" {
		if firstFilenameChar == "/" {
			return baseHost + string(filename[1:len(filename)])
		} else {
			return baseHost + filename
		}
	} else {
		if firstFilenameChar == "/" {
			return baseHost + filename
		} else {
			return baseHost + "/" + filename
		}
	}
}
