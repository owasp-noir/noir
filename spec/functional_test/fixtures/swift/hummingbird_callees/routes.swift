import Hummingbird

func routes(_ router: Router<some RequestContext>) {
    router.post("users/:id") { request, context -> User in
        let id = try context.parameters.require("id")
        let payload = try await request.decode(as: CreateUser.self, context: context)
        let user = try UserService.build(payload)
        AuditLog.write("create", id: id)
        return try await user.save()
    }

    router.get("search") { request, context -> String in
        let template = """
        }
        """
        // }
        let query = request.uri.queryParameters.get("q")
        SearchMetrics.record(query)
        return SearchService.render(query)
    }

    router.get("ping") { request, context in PingService.pong() }

    router.get("delayed")
    { request, context in
        DelayService.wait()
    } ; OutsideService.noise()
}
