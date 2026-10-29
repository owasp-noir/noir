package main

import (
	"net/http"

	"github.com/org/beta-service/internal/mw"
)

func main() {
	mux := http.NewServeMux()
	mux.Handle("GET /beta", mw.Wrap(http.HandlerFunc(h)))
	http.ListenAndServe(":1", mux)
}

func h(w http.ResponseWriter, r *http.Request) {}
