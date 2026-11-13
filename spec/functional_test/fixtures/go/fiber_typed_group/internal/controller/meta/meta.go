package meta

import (
	"github.com/gofiber/fiber/v2"

	"example.com/typedgroup/internal/server/svr"
)

// A controller type sharing the wrapper's name in another package.
type Meta struct{}

func RegisterMeta(meta *svr.Meta, c Meta) {
	meta.Get("/health", c.Health)
}

func (c Meta) Health(ctx *fiber.Ctx) error {
	return ctx.SendString("ok")
}
