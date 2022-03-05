package models

type Project struct {
	BasePath  string
	Language  string
	Framework string
	PublicDir []string
	RouteFile []string
}
