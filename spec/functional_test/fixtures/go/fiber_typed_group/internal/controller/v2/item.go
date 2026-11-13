package v2

import (
	"github.com/gofiber/fiber/v2"

	"example.com/typedgroup/internal/server/svr"
)

func RegisterItem(v2 *svr.V2) {
	v2.Get("/items", listItems)
	items := v2.Group("/items")
	items.Get("/:itemId", getItem)
}

func RegisterLegacy(legacy *svr.Legacy) {
	legacy.Get("/old", listItems)
}

func RegisterPartner(partner *svr.Partner) {
	partner.Get("/feed", listItems)
}

func listItems(c *fiber.Ctx) error {
	return c.JSON([]string{})
}

func getItem(c *fiber.Ctx) error {
	return c.SendString(c.Params("itemId"))
}
