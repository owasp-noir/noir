package main

import (
	"net/http"

	"github.com/zeromicro/go-zero/rest"
	"github.com/zeromicro/go-zero/rest/httpx"
)

func main() {
	server := rest.MustNewServer(rest.RestConf{
		Host: "localhost",
		Port: 8888,
	})
	defer server.Stop()

	server.Post("/users", createUser)
	server.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		httpx.OkJson(w, map[string]bool{"ok": true})
	})
	server.Get("/profile", listProfile)

	server.Start()
}
