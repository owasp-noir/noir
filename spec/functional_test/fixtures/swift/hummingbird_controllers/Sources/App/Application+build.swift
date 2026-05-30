import Hummingbird

func buildApplication() -> some ApplicationProtocol {
    let router = Router()

    // Look-alike `.get`/`.delete` calls on non-router receivers — must
    // never be reported as endpoints.
    _ = environment.get("LOG_LEVEL")
    _ = sessionStorage.get(key: "session")
    _ = try await repository.delete(id: identifier)

    router.get("health") { _, _ in .ok }              // GET /health
    router.on("status", method: .HEAD) { _, _ in .ok } // HEAD /status
    router.ws("socket") { _, _ in .upgrade([:]) }      // GET /socket

    // RouteCollection controller mounted at an explicit path.
    router.addRoutes(UserController().endpoints, atPath: "/users")
    // Controller bound to a router group.
    TodoController().addRoutes(to: router.group("api/todos"))

    return Application(router: router)
}
