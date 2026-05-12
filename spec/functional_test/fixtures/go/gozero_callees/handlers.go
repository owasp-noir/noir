package main

import (
	"net/http"

	"github.com/zeromicro/go-zero/rest/httpx"
)

func createUser(w http.ResponseWriter, r *http.Request) {
	name := r.FormValue("name")
	user := saveUser(name)
	auditLog(user)
	httpx.OkJson(w, map[string]string{"id": user})
}

func listProfile(w http.ResponseWriter, r *http.Request) {
	data := buildProfile()
	auditLog(data)
	httpx.OkJson(w, map[string]string{"profile": data})
}
