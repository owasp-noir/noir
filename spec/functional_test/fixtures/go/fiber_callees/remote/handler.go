package remote

import "github.com/gofiber/fiber/v2"

func RemoteProfile(c *fiber.Ctx) error {
	profile := loadRemoteProfile(c)
	return c.JSON(profile)
}

func loadRemoteProfile(c *fiber.Ctx) string {
	return c.Params("id")
}

func RemoteFactory(prefix string) fiber.Handler {
	return func(c *fiber.Ctx) error {
		profile := buildRemoteFactoryProfile(prefix, c)
		return c.JSON(profile)
	}
}

func buildRemoteFactoryProfile(prefix string, c *fiber.Ctx) string {
	return prefix + ":" + c.Params("name")
}

type RemoteController struct{}

func NewRemoteController() *RemoteController {
	return &RemoteController{}
}

func (rc *RemoteController) Show(c *fiber.Ctx) error {
	profile := loadRemoteProfile(c)
	return c.JSON(profile)
}
