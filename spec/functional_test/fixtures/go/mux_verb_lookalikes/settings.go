package main

// Same package as the router, so it is parsed as a route candidate — but
// these are config, cache and logger calls, not registrations.
func loadSettings() {
	timeout := env.Get("APP_TIMEOUT", "30s")
	store.Put("timeout", timeout)
	log.Any("settings", timeout)
	sessions.Delete("stale")
}
