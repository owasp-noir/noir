package main

import (
	"net/http"

	sw "example.com/petstoremux/go"
)

func main() {
	router := sw.NewRouter()
	_ = http.ListenAndServe(":8080", router)
}
