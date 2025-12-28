import Kitura

let router = Router()

// Basic GET route
router.get("/hello") { request, response, next in
    response.send("Hello, World!")
    next()
}

// POST route with body
router.post("/users") { request, response, next in
    let body = request.body
    response.send("User created")
    next()
}

// GET with path parameter
router.get("/users/:userID") { request, response, next in
    let userID = request.parameters["userID"]
    response.send("User ID: \(userID ?? "unknown")")
    next()
}

// PUT with multiple path parameters
router.put("/users/:userID/posts/:postID") { request, response, next in
    let userID = request.parameters["userID"]
    let postID = request.parameters["postID"]
    response.status(.OK)
    next()
}

// GET with query parameter
router.get("/search") { request, response, next in
    let query = request.queryParameters["q"]
    let sort = request.queryParameters["sort"]
    response.send("Searching for: \(query ?? "nothing")")
    next()
}

// POST with authentication header
router.post("/api/login") { request, response, next in
    let auth = request.headers["Authorization"]
    response.send("Login successful")
    next()
}

// GET with cookie
router.get("/profile") { request, response, next in
    let sessionID = request.cookies["session"]
    response.send("Session: \(sessionID ?? "none")")
    next()
}

// DELETE route
router.delete("/users/:id") { request, response, next in
    let id = request.parameters["id"]
    response.status(.OK)
    next()
}

// PATCH route
router.patch("/articles/:articleID") { request, response, next in
    let articleID = request.parameters["articleID"]
    let body = request.body
    response.status(.OK)
    next()
}

// Another simple GET route
router.get("/status") { request, response, next in
    response.send("API is running")
    next()
}

Kitura.addHTTPServer(onPort: 8080, with: router)
Kitura.run()
