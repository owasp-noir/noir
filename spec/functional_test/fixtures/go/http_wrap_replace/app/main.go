package main

import (
	"net/http"

	"example.com/upstream/authlib/mw"
)

func main() {
	mux := http.NewServeMux()
	mux.Handle("GET /forked", mw.Wrap(http.HandlerFunc(h)))
	http.ListenAndServe(":1", mux)
}

func h(w http.ResponseWriter, r *http.Request) {}
