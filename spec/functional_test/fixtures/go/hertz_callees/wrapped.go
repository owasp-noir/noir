package main

import (
	"github.com/cloudwego/hertz/pkg/app"
	"github.com/cloudwego/hertz/pkg/app/server"
	remote "github.com/hahwul/hertz-callees-fixture/remote"
)

func routeMw() []app.HandlerFunc {
	return nil
}

func registerWrapped(h *server.Hertz) {
	h.GET("/wrapped-feed", append(routeMw(), remote.Feed)...)
}
