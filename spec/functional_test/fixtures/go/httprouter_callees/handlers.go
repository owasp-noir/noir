package main

import (
	"net/http"

	"github.com/julienschmidt/httprouter"
)

func createUser(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
	name := r.FormValue("name")
	user := saveUser(name)
	auditLog(user)
	w.Write([]byte(user))
}

func listProfile(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
	data := buildProfile()
	auditLog(data)
	w.Write([]byte(data))
}
