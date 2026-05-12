package main

import (
	"net/http"
)

func createUser(w http.ResponseWriter, r *http.Request) {
	name := r.FormValue("name")
	user := saveUser(name)
	auditLog(user)
	w.Write([]byte(user))
}

func listProfile(w http.ResponseWriter, r *http.Request) {
	data := buildProfile()
	auditLog(data)
	w.Write([]byte(data))
}
