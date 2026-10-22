import Vapor

func innerRoutes(_ app: Application) throws {
    app.get("inner") { req in
        "ok"
    }
}
