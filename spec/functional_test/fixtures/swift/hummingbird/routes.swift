import Hummingbird

func routes(_ router: Router<some RequestContext>) {
    // Basic GET route
    router.get("hello") { request, context -> String in
        return "Hello, world!"
    }
    
    // POST route with body
    router.post("users") { request, context -> User in
        let user = try await request.decode(as: User.self, context: context)
        return user
    }
    
    // GET with path parameter
    router.get("users/:userID") { request, context -> String in
        let userID = try context.parameters.require("userID")
        return "User ID: \(userID)"
    }
    
    // PUT with multiple path parameters
    router.put("users/:userID/posts/:postID") { request, context -> HTTPResponse.Status in
        let userID = try context.parameters.require("userID")
        let postID = try context.parameters.require("postID")
        return .ok
    }
    
    // GET with query parameter
    router.get("search") { request, context -> String in
        let query = request.uri.queryParameters.get("q")
        let sort = request.uri.queryParameters.get("sort")
        return "Searching for: \(query ?? "nothing")"
    }
    
    // POST with authentication header
    router.post("api/login") { request, context -> Token in
        let auth = request.headers["Authorization"]
        let credentials = try await request.decode(as: Credentials.self, context: context)
        return authenticateUser(credentials)
    }
    
    // GET with cookie
    router.get("profile") { request, context -> String in
        let sessionID = request.cookies["session"]?.value
        return "Session: \(sessionID ?? "none")"
    }
    
    // DELETE route
    router.delete("users/:id") { request, context -> HTTPResponse.Status in
        let id = try context.parameters.require("id")
        return .ok
    }
    
    // PATCH route
    router.patch("articles/:articleID") { request, context -> Article in
        let articleID = try context.parameters.require("articleID")
        let updates = try await request.decode(as: ArticleUpdate.self, context: context)
        return updates
    }
    
    // Another simple GET route
    router.get("status") { request, context -> String in
        return "API is running"
    }
}
