package example

import com.twitter.finatra.http.Controller
import com.twitter.finagle.http.Request

// scalafmt wraps a long header, so the body brace lands on a later line.
class OrderController @Inject()(service: OrderService) extends Controller
  with Logging {
  get("/orders/:id") { request: Request => "order" }
}
