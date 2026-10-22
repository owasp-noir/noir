// Calls that share a verb name with the router API but are not routes:
// a settings reader, a key-value store, a structured logger and a cache
// lookup into an out-parameter. Each used to come out as an endpoint
// (`GET /_APP_SCANNER`, `PUT /timeout`, `ANY /panic`,
// `GET /latest_version_cache`).
package main

import "github.com/gofiber/fiber/v2"

func main() {
	app := fiber.New()
	app.Get("/users", listUsers)
	app.Post("/users", createUser)

	if env.Get("_APP_SCANNER", config.EnableOn) == config.EnableOn {
		defer func() {
			if r := recover(); r != nil {
				mlog.Error("recovered", mlog.Any("panic", r))
			}
		}()
	}
	store.Put("timeout", timeout)

	var cached string
	latestVersionCache.Get("latest_version_cache", &cached)
}

func listUsers(c *fiber.Ctx) error  { return nil }
func createUser(c *fiber.Ctx) error { return nil }
