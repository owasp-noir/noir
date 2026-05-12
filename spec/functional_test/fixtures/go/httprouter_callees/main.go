package main

import (
	"net/http"

	"github.com/julienschmidt/httprouter"
)

func main() {
	r := httprouter.New()
	r.POST("/users", createUser)
	r.GET("/healthz", func(w http.ResponseWriter, req *http.Request, ps httprouter.Params) {
		w.Write([]byte("ok"))
	})
	r.Handle("GET", "/profile", listProfile)
	http.ListenAndServe(":8080", r)
}
