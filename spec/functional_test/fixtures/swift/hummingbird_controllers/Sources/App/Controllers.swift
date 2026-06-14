import Hummingbird

// `addRoutes(to:)` + a fluent builder chain whose `use:` handlers are
// referenced through `self.`. The "/api/todos" prefix is lifted from the
// call site in Application+build.swift.
struct TodoController<Context: RequestContext> {
    func addRoutes(to group: RouterGroup<Context>) {
        group
            .get(use: self.list)              // GET    /api/todos
            .get(":id", use: self.get)        // GET    /api/todos/:id
            .post(use: self.create)           // POST   /api/todos
            .patch(":id", use: self.update)   // PATCH  /api/todos/:id
            .delete(":id", use: self.delete)  // DELETE /api/todos/:id

        // A builder chain that *opens* with `.add(middleware:)`: the verb
        // steps must still attach (regression for chain-start detection).
        group.add(middleware: AuthMiddleware())
            .get("me", use: self.current)     // GET    /api/todos/me
            .post("logout", use: self.logout) // POST   /api/todos/logout
    }

    func list(_ request: Request, context: Context) async throws -> [Todo] { [] }
    func get(_ request: Request, context: Context) async throws -> Todo? { nil }
    func create(_ request: Request, context: Context) async throws -> Todo { Todo() }
    func update(_ request: Request, context: Context) async throws -> Todo { Todo() }
    func delete(_ request: Request, context: Context) async throws -> HTTPResponse.Status { .ok }
    func current(_ request: Request, context: Context) async throws -> Todo { Todo() }
    func logout(_ request: Request, context: Context) async throws -> HTTPResponse.Status { .ok }
}

// `RouteCollection` mounted via `addRoutes(_:atPath:)`; routes inherit the
// "/users" prefix. The trailing-closure builder chain must resume across
// each closure body.
struct UserController {
    var endpoints: RouteCollection<AppRequestContext> {
        let routes = RouteCollection(context: AppRequestContext.self)
        routes.post(use: self.signup)         // POST /users
        routes.get(":id", use: self.profile)  // GET  /users/:id

        routes.group("session")
            .add(middleware: SessionMiddleware())
            .post("login") { _, _ in .ok }     // POST /users/session/login
            .post("logout") { _, _ in .ok }    // POST /users/session/logout
        return routes
    }

    func signup(_ request: Request, context: AppRequestContext) async throws -> User { User() }
    func profile(_ request: Request, context: AppRequestContext) async throws -> User { User() }
}
