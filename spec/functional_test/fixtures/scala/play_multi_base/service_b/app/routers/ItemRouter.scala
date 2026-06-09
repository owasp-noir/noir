package routers

import play.api.mvc.Results
import play.api.routing.SimpleRouter
import play.api.routing.sird._

class ItemRouter extends SimpleRouter {
  override def routes = {
    case GET(p"/from-b") => Results.Ok("b")
  }
}
