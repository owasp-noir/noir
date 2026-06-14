package main

import (
	restful "github.com/emicklei/go-restful/v3"
)

type User struct {
	ID   string
	Name string
}

type UserResource struct{}

func (u UserResource) WebService() *restful.WebService {
	ws := new(restful.WebService)
	ws.Path("/users").
		Consumes(restful.MIME_JSON).
		Produces(restful.MIME_JSON)

	ws.Route(ws.GET("/").To(u.findAllUsers).
		Writes([]User{}))

	ws.Route(ws.GET("/{user-id}").To(u.findUser).
		Param(ws.PathParameter("user-id", "identifier of the user").DataType("integer")).
		Param(ws.QueryParameter("verbose", "verbose output")).
		Writes(User{}))

	ws.Route(ws.POST("").To(u.createUser).
		Reads(User{}))

	ws.Route(ws.PUT("/{user-id}").To(u.updateUser).
		Param(ws.PathParameter("user-id", "identifier of the user")).
		Reads(User{}))

	ws.Route(ws.DELETE("/{user-id}").To(u.removeUser).
		Param(ws.PathParameter("user-id", "identifier of the user")))

	return ws
}

func (u UserResource) findAllUsers(req *restful.Request, resp *restful.Response) {}
func (u UserResource) findUser(req *restful.Request, resp *restful.Response)    {}
func (u UserResource) createUser(req *restful.Request, resp *restful.Response)  {}
func (u UserResource) updateUser(req *restful.Request, resp *restful.Response)  {}
func (u UserResource) removeUser(req *restful.Request, resp *restful.Response)  {}
