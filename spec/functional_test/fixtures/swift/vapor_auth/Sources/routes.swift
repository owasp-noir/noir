import Vapor

func routes(_ app: Application) throws {
    app.get("public") { req in
        return "public"
    }

    let protected = app.grouped(UserAuthenticator())
    protected.get("profile") { req in
        let user = try req.auth.require(User.self)
        return "Hello, \(user.name)"
    }

    protected.post("api", "data") { req in
        return "created"
    }

    app.get("health") { req in
        return "ok"
    }
}
