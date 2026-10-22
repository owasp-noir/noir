package main

import (
	"net/http"

	"github.com/julienschmidt/httprouter"
)

func listC(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
	_ = r.URL.Query().Get("qc")
}

func main() {
	router := httprouter.New()
	router.GET("/a", listA)
	router.GET("/b", listB)
	router.GET("/c", listC)
	http.ListenAndServe(":8080", router)
}

func listA(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
	_ = r.URL.Query().Get("qa")
}

func listB(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
	_ = r.URL.Query().Get("qb")
}
