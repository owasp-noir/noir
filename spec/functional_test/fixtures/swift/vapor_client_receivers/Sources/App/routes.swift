import Vapor

// Real routes registered on the application and on `app.routes`.
func routes(_ app: Application) throws {
    app.get("health") { req in
        "ok"
    }

    app.routes.grouped("api").get("status") { req in
        "up"
    }
}
