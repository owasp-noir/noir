package meta

import (
	"github.com/gofiber/fiber/v2"

	"example.com/typedgroup/internal/server/svr"
	"example.com/typedgroup/internal/service"
)

type AdminController struct {
	AdminService *service.Admin
}

func RegisterAdmin(admin *svr.Admin, c AdminController) {
	admin.Get("/bonjour", c.Bonjour)
	admin.Post("/purge", c.Purge)
}

func (c AdminController) Bonjour(ctx *fiber.Ctx) error {
	return ctx.SendString("bonjour")
}

func (c AdminController) Purge(ctx *fiber.Ctx) error {
	return ctx.SendStatus(fiber.StatusNoContent)
}
