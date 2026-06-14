import Hummingbird
import HummingbirdRouter

// The `HummingbirdRouter` result-builder DSL: routes are declared
// structurally inside a `RouterBuilder { }` block, not via `router.get(...)`.
func buildApplication() -> some ApplicationProtocol {
    let router = RouterBuilder(context: AppRequestContext.self) {
        // Middleware elements — PascalCase, but not route primitives.
        LogRequestsMiddleware(.info)

        // Top-level route with an inline trailing-closure handler.
        Get("/health") { _, _ -> HTTPResponse.Status in
            .ok                                  // GET /health
        }

        // A controller whose `body` is spliced in at the root prefix.
        UserController()

        // An inline group with a `handler:`-style route.
        RouteGroup("admin") {
            Get("stats", handler: self.stats)    // GET /admin/stats
        }
    }

    return Application(router: router)
}
