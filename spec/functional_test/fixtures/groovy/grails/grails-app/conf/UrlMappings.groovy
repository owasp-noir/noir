class UrlMappings {
    static mappings = {
        get "/api/health"(controller: "health", action: "ping")
        post "/api/login"(controller: "auth", action: "login")
        // `method:` argument on a verbless mapping should win over the
        // default GET fallback.
        "/api/users"(controller: "user", action: "create", method: "POST")
    }
}
