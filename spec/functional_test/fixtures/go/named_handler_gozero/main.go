package main

import (
	"net/http"

	"github.com/zeromicro/go-zero/rest"
)

func listC(w http.ResponseWriter, r *http.Request) {
	_ = r.FormValue("qc")
}

func main() {
	server := rest.MustNewServer(rest.RestConf{})
	server.Get("/a", listA)
	server.Get("/b", listB)
	server.Get("/c", listC)
	server.Start()
}

func listA(w http.ResponseWriter, r *http.Request) {
	_ = r.FormValue("qa")
}

func listB(w http.ResponseWriter, r *http.Request) {
	_ = r.FormValue("qb")
}
