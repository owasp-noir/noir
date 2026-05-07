class UrlMappings {
    static mappings = {
        get "/api/health"(controller: "health", action: "ping")
        post "/api/login"(controller: "auth", action: "login")
    }
}
