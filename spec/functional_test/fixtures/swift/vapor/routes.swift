import Vapor

func routes(_ app: Application) throws {
    // Non-router look-alikes: a static type method and an env lookup whose
    // receivers are not router-like — must NOT be reported as endpoints.
    _ = Environment.get("DATABASE_URL")
    _ = Environment.get("LOG_LEVEL")

    // Basic GET route
    app.get("hello") { req -> String in
        return "Hello, world!"
    }

    // Multi-segment grouped base (`app.routes.grouped(...)`): the new group
    // must register as router-like with the composed prefix.
    let v2 = app.routes.grouped("v2")
    v2.get("ping") { req -> String in
        return "pong"                            // GET /v2/ping
    }

    // POST route with body
    app.post("users") { req -> EventLoopFuture<User> in
        let user = try req.content.decode(User.self)
        return user.save(on: req.db).map { user }
    }
    
    // GET with path parameter
    app.get("users", ":userID") { req -> String in
        let userID = req.parameters.get("userID")
        return "User ID: \(userID ?? "unknown")"
    }
    
    // PUT with multiple path parameters
    app.put("users", ":userID", "posts", ":postID") { req -> EventLoopFuture<HTTPStatus> in
        let userID = req.parameters.get("userID")
        let postID = req.parameters.get("postID")
        return req.eventLoop.future(.ok)
    }
    
    // GET with query parameter
    app.get("search") { req -> String in
        let query = req.query["q"]
        let sort = req.query["sort"]
        return "Searching for: \(query ?? "nothing")"
    }
    
    // POST with authentication header
    app.post("api", "login") { req -> EventLoopFuture<Token> in
        let auth = req.headers["Authorization"].first
        let credentials = try req.content.decode(Credentials.self)
        return authenticateUser(credentials, on: req.db)
    }
    
    // GET with cookie
    app.get("profile") { req -> String in
        let sessionID = req.cookies["session"]?.string
        return "Session: \(sessionID ?? "none")"
    }
    
    // DELETE route. The Fluent `.delete(on:)` and HTTP-client `.get(...)`
    // calls inside the handler use non-router receivers and must NOT be
    // reported as endpoints.
    app.delete("users", ":id") { req -> EventLoopFuture<HTTPStatus> in
        let id = req.parameters.get("id")
        _ = req.client.get("http://example.com/health")
        return User.find(id, on: req.db).flatMap { user in
            user!.delete(on: req.db)
        }
    }
    
    // PATCH route
    app.patch("articles", ":articleID") { req -> EventLoopFuture<Article> in
        let articleID = req.parameters.get("articleID")
        let updates = try req.content.decode(ArticleUpdate.self)
        return updateArticle(articleID, updates, on: req.db)
    }
    
    // Another simple GET route
    app.get("status") { req -> String in
        return "API is running"
    }
}
