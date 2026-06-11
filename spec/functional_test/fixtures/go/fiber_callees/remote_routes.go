package main

import (
	"github.com/gofiber/fiber/v2"
	"github.com/hahwul/fiber-callees-fixture/remote"
)

func registerRemote(app *fiber.App) {
	controller := remote.NewRemoteController()
	app.Get("/remote/:id", remote.RemoteProfile)
	app.Get("/remote-factory/:name", remote.RemoteFactory("profiles"))
	app.Get("/remote-controller/:id", controller.Show)
}
