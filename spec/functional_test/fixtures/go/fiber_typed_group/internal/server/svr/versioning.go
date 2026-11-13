package svr

import (
	"crypto/subtle"
	"os"
	"strings"

	"github.com/gofiber/fiber/v2"
)

type V2 struct {
	fiber.Router
}

type Admin struct {
	fiber.Router
}

type Meta struct {
	fiber.Router
}

// Built twice, from two groups: its routes keep no prefix.
type Legacy struct {
	fiber.Router
}

// Built from a group handed in: the prefix is the caller's, not read.
type Partner struct {
	fiber.Router
}

func CreateEndpointGroups(app *fiber.App) (*V2, *Admin, *Meta) {
	v2 := app.Group("/api/v2", func(c *fiber.Ctx) error {
		c.Set("X-Api-Version", "2")
		return c.Next()
	})

	admin := app.Group("/api/admin", func(c *fiber.Ctx) error {
		key := strings.TrimSpace(strings.TrimPrefix(c.Get(fiber.HeaderAuthorization), "Bearer"))
		if subtle.ConstantTimeCompare([]byte(key), []byte(os.Getenv("ADMIN_KEY"))) != 1 {
			return c.SendStatus(fiber.StatusUnauthorized)
		}
		return c.Next()
	})

	meta := app.Group("/api/_")

	return &V2{Router: v2}, &Admin{Router: admin}, &Meta{Router: meta}
}

func CreateLegacyGroups(app *fiber.App) (*Legacy, *Legacy) {
	a := app.Group("/legacy/a")
	b := app.Group("/legacy/b")
	return &Legacy{Router: a}, &Legacy{Router: b}
}

func CreatePartner(api fiber.Router) *Partner {
	partner := api.Group("/partner")
	return &Partner{Router: partner}
}
