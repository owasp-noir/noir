package example

import com.twitter.finatra.http.Controller
import com.twitter.finagle.http.Request
import javax.inject.Inject

class UserController @Inject()(
  service: UserService
) extends Controller {
  get("/users/:id") { request: Request =>
    service.find(request.params("id"), request.params(/* projection */ "fields"))
  }

  post("/users") { request: Request => "ok" }

  // get("/commented") { request: Request => "no" }

  prefix("/admin") {
    delete("/users/:id") { request: Request => "x" }
    // A brace char literal must not keep this prefix block open.
    get("/raw") { request: Request => request.contentString.indexOf('{') }

    prefix("/v2") {
      put[Request, String]("/settings") { request: Request =>
        request.getParam("mode")
      }
    }
  }

  get("/files/:*") { request: Request => "file" }

  any("/ping") { request: Request => "pong" }

  filter[AuthFilter].get("/secured") { request: Request =>
    val token = request.params.get("token")
    token.getOrElse("")
  }

  filter[AuthFilter].filter[AuditFilter].post("/audited") { request: Request => "ok" }

  filter[AuthFilter].prefix("/me") {
    get("/profile") { request: Request => "me" }
  }
}

// Not a controller: a client wrapper whose `get("...")` is an outbound call.
class UserClient(http: HttpClient) {
  def fetch(): String = get("/not-a-route")
}
