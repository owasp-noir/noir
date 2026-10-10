package example

import com.twitter.finatra.http.Controller
import com.twitter.finagle.http.Request
import javax.inject.Inject

class UserController @Inject()(
  service: UserService
) extends Controller {
  get("/users/:id") { request: Request =>
    service.find(request.params("id"), request.params("fields"))
  }

  post("/users") { request: Request => "ok" }

  // get("/commented") { request: Request => "no" }

  prefix("/admin") {
    delete("/users/:id") { request: Request => "x" }

    prefix("/v2") {
      put[Request, String]("/settings") { request: Request =>
        request.getParam("mode")
      }
    }
  }

  get("/files/:*") { request: Request => "file" }

  any("/ping") { request: Request => "pong" }
}

// Not a controller: a client wrapper whose `get("...")` is an outbound call.
class UserClient(http: HttpClient) {
  def fetch(): String = get("/not-a-route")
}
