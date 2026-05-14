import Kitura

let router = Router()

router.post("/users/:id") { request, response, next in
    let id = request.parameters["id"]
    let payload = request.body
    let user = UserService.build(payload)
    AuditLog.write("create", id: id)
    response.send(try ResponseBuilder.created(user))
    next()
}

router.get("/search") { request, response, next in
    let template = """
    }
    """
    // }
    let query = request.queryParameters["q"]
    SearchMetrics.record(query)
    response.send(SearchService.render(query))
    next()
}

router.get("/health") { request, response, next in HealthService.check(response) }

router.get("/delayed")
{ request, response, next in
    DelayService.wait()
} ; OutsideService.noise()

/*
func showProfile(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
    CommentedService.bad()
}
*/
func showProfile(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws

{
    let session = request.cookies["session"]
    let profile = try ProfileService.load(session)
    response.send(ProfilePresenter.render(profile))
    next()
}

router.get("/profile", handler: showProfile)
