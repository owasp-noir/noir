import Vapor

func routes(_ app: Application) throws {
    app.post("users", ":id") { req -> EventLoopFuture<Response> in
        let id = req.parameters.get("id")
        let payload = try req.content.decode(CreateUser.self)
        let user = try UserService.build(payload)
        AuditLog.write("create", id: id)
        return user.save(on: req.db).map { saved in
            try ResponseBuilder.created(saved)
        }
    }

    app.get("health") { req -> String in
        let template = """
        }
        """
        // }
        HealthService.check()
        return "ok"
    }

    app.get("ping") { req in PingService.pong() }
}
