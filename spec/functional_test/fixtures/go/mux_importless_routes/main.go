package main

import (
	"fmt"
	"net/http"

	"github.com/gorilla/mux"
)

type RouteRegistrar interface {
	HandleFunc(string, func(http.ResponseWriter, *http.Request)) *mux.Route
}

func main() {
	r := mux.NewRouter()
	registerRoutes(r)
}

func getFeature(w http.ResponseWriter, r *http.Request) {
	fmt.Fprint(w, "ok")
}

func updateFeature(w http.ResponseWriter, r *http.Request) {
	fmt.Fprint(w, "ok")
}
