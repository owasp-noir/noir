// `github.com/minio/mux` is a maintained hard fork of gorilla/mux with the
// same routing API. A project that imports only the fork used to detect as
// `go_mux` (MinIO's own go.mod happens to carry gorilla/mux as an indirect
// dependency) and then match no file, so every route went missing.
package main

import (
	"net/http"

	"github.com/minio/mux"
)

func main() {
	router := mux.NewRouter()

	router.Methods(http.MethodGet).Path("/objects/{object}").HandlerFunc(getObject)
	router.Methods(http.MethodPut).Path("/objects/{object}").HandlerFunc(putObject)

	api := router.PathPrefix("/admin").Subrouter()
	api.Methods(http.MethodDelete).Path("/heal").HandlerFunc(heal)

	http.ListenAndServe(":9000", router)
}

func getObject(w http.ResponseWriter, r *http.Request) {}
func putObject(w http.ResponseWriter, r *http.Request) {}
func heal(w http.ResponseWriter, r *http.Request)      {}
