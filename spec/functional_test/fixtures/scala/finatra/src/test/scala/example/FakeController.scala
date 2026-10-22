package example

import com.twitter.finatra.http.Controller

class FakeController extends Controller {
  get("/test-only") { request: Request => "fake" }
}
