package main

import (
	restful "github.com/emicklei/go-restful/v3"
)

// A second WebService in another file, mounted at its own prefix, to
// exercise per-WebService Path() resolution.
func registerHealth(container *restful.Container) {
	ws := new(restful.WebService)
	ws.Path("/api/v1/health")
	ws.Route(ws.GET("/ping").To(ping))
	ws.Route(ws.HEAD("/ready").To(ready))
	container.Add(ws)
}

func ping(req *restful.Request, resp *restful.Response)  {}
func ready(req *restful.Request, resp *restful.Response) {}
