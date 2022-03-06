package models

type AutoDetect struct {
	Name     string
	Patterns []AutoDetectPattern
}

type AutoDetectPattern struct {
	File  string
	Ext   string
	Match string
}
