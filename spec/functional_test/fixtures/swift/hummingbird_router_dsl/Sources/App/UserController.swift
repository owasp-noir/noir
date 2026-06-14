import Hummingbird
import HummingbirdRouter

// A `RouterController` whose `body` declares routes with the result-builder
// DSL. The enclosing `RouteGroup("user")` prefixes every nested primitive.
struct UserController: RouterController {
    typealias Context = AppRequestContext

    var body: some RouterMiddleware<Context> {
        RouteGroup("user") {
            // No path → bound to the group root.
            Put(handler: self.create)               // PUT  /user
            Post("signup", handler: self.signup)    // POST /user/signup

            // Trailing-closure handler. The PascalCase constructor inside the
            // closure is a model, NOT a route, and must not be emitted.
            Get("login") { request, context -> Token in
                let credentials = try await request.decode(as: Credentials.self, context: context)
                let token = Token(value: "stub")    // look-alike, must be ignored
                return token
            }

            // Nested group — composes the prefix further.
            RouteGroup("mfa") {
                Post("enable", handler: self.enable) // POST /user/mfa/enable
            }
        }
    }

    @Sendable func create(_ request: Request, context: Context) async throws -> User {
        let user = try await request.decode(as: User.self, context: context)
        return user
    }

    @Sendable func signup(_ request: Request, context: Context) async throws -> User {
        try await request.decode(as: User.self, context: context)
    }

    @Sendable func enable(_ request: Request, context: Context) async throws -> HTTPResponse.Status {
        .ok
    }
}

// A custom middleware conforming via `: RouterMiddleware` (not `some
// RouterMiddleware`) — the conformance must not open a route-emitting scope,
// so the `Post(...)`-looking constructor in its `handle` body is never a route.
struct RedirectMiddleware<Context: RequestContext>: RouterMiddleware {
    func handle(_ request: Request, context: Context, next: Responder) async throws -> Response {
        let audit = Post(event: "redirect")   // look-alike, must be ignored
        return try await next(request, context)
    }
}
