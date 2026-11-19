package handler

import "net/http"

func Noop(w http.ResponseWriter, r *http.Request) {}

func Search(w http.ResponseWriter, r *http.Request) {
	_ = r.URL.Query().Get("q")
}
