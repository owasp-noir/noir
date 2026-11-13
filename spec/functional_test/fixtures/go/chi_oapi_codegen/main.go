package main

import (
	"net/http"

	"example.com/shop/api"
)

func main() {
	http.ListenAndServe(":8080", api.Handler(api.Impl{}))
}
