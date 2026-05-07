class PluginUrlMappings {
    static mappings = {
        get "/plugin/status"(controller: "plugin", action: "status")
    }
}
