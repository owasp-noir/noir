import play.api.mvc._
import play.api.routing.Router
import play.api.routing.sird._

// Play's `test/` root: a router built for a spec is not served.
class RouterSpec {
  val router = Router.from { case GET(p"/only-in-test") => Action(Results.Ok("t")) }
}
