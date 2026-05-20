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

        // Named URL mapping — Grails uses the `name <id>:` prefix for
        // reverse URL generation. The mapping itself is otherwise the
        // same verbless paren-form.
        name reports: "/api/reports"(controller: "reports", action: "list")

        // `uri:` mapping — a path that redirects to another internal URI
        // (no controller/action pair). Still an exposed endpoint.
        "/api/legacy-alias"(uri: "/api/legacy")

        // Singular `resource:` shortcut — singleton REST resource
        // exposing GET/POST/PUT/PATCH/DELETE on the path itself.
        "/api/profile"(resource: "profile")
    }
}
