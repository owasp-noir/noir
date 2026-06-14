import Vapor

// A `RoutesBuilder` extension: bare `grouped(...)` and `self.<verb>` are
// router-like even though there is no named router variable. The controller
// method call inside the handler (`adminController.delete(...)`) shares a verb
// name with a route but is NOT router-like, so it must not become an endpoint.
extension RoutesBuilder {
    func registerAdminRoutes() {
        let admin = grouped("admin")
        admin.get("dashboard") { req -> String in   // GET /admin/dashboard
            return "ok"
        }
        self.post("purge") { req -> String in        // POST /purge
            adminController.delete(req)               // must NOT be DELETE /
            return "ok"
        }
    }
}
