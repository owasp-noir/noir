package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"sort"

	reference "example.org/reference/src"
	"github.com/gin-gonic/gin"
)

type route struct {
	Method string `json:"method"`
	Path   string `json:"path"`
}

func main() {
	if len(os.Args) == 2 && os.Args[1] == "--version" {
		fmt.Println(gin.Version)
		return
	}
	gin.SetMode(gin.ReleaseMode)
	var rows []route
	for _, r := range reference.Engine().Routes() {
		rows = append(rows, route{r.Method, r.Path})
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].Path == rows[j].Path {
			return rows[i].Method < rows[j].Method
		}
		return rows[i].Path < rows[j].Path
	})
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(rows); err != nil {
		log.Fatal(err)
	}
}
