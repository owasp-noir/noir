class UrlMappings {
    static mappings = {
        get "/api/health"(controller: "health", action: "ping")
        post "/api/login"(controller: "auth", action: "login")
        // `method:` argument on a verbless mapping should win over the
        // default GET fallback.
        "/api/users"(controller: "user", action: "create", method: "POST")

        // REST resources shortcut.
        "/api/orders"(resources: "order")

        // Nested `group` block — the `/v2` prefix should propagate to
        // every mapping inside the closure.
        group "/v2", {
            get "/items"(controller: "item", action: "list")
        }

        // Closure-form mapping declaring controller/action/method via
        // assignment statements.
        "/api/legacy" {
            controller = "legacy"
            action = "handle"
            method = "POST"
        }
    }
}
