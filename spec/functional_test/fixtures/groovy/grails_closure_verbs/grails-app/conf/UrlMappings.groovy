class UrlMappings {
    static mappings = {
        // Closure form with a nested `controller = { ... }` closure: the verb
        // map after it is POST-only, so no GET may be fabricated.
        "/api/fulfillments" {
            controller = { "fulfillmentApi" }
            action = [POST: "save"]
        }

        // Several verbs on one mapping -> one endpoint per verb.
        "/api/widgets" {
            controller = { "widgetApi" }
            action = [GET: "list", POST: "create"]
        }

        // Flat (no nested closure) verb map.
        "/api/gadgets" {
            controller = "gadgetApi"
            action = [DELETE: "purge"]
        }

        // No verb map: the `method =` assignment still wins, and a mapping
        // with neither is a GET.
        "/api/legacy" {
            controller = { "legacyApi" }
            action = "handle"
            method = "PUT"
        }

        "/api/status" {
            controller = { "statusApi" }
            action = "show"
        }

        // Response-code closures configure error pages, not endpoints.
        "500" {
            controller = { "errors" }
            action = [GET: "handleException"]
        }
    }
}
