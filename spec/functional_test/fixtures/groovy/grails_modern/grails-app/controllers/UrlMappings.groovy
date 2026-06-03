// In Grails 3+ the canonical UrlMappings file lives under
// `grails-app/controllers/` (it sat in `grails-app/conf/` on 1.x/2.x).
class UrlMappings {
    static mappings = {
        // Default convention mapping — declares no controller/action, so it
        // is not itself a routable endpoint.
        "/$controller/$action?/$id?(.$format)?"()

        // GString `${name}` path variable plus an optional content-format
        // suffix `(.${format})` that must be stripped from the URL.
        "/image/${imageId}(.${format})"(controller: 'image', action: 'show')

        // Per-verb action dispatch map — one endpoint per HTTP verb.
        "/api/v1/widget/$id"(controller: 'widget') {
            action = [GET: 'show', PUT: 'update']
        }

        // REST resources shortcut → six endpoints.
        "/api/v1/books"(resources: 'book')

        // Response-code mappings configure error pages, not endpoints.
        "404"(controller: 'error', action: 'notFound')
        "500"(view: '/error')
    }
}
