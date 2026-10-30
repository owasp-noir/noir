package com.example

import play.api.mvc._
import play.api.routing.Router
import play.api.routing.sird._

class ExtraRouters(prefix: String) {
  // Bound to a name and prefixed where it is used.
  val api: Router = Router.from {
    case GET(p"/members/$id") => Action(Results.Ok(id))
  }
  val mountedApi = api.withPrefix("/api")

  val infix = Router.from { case GET(p"/feed") => Action(Results.Ok("feed")) } withPrefix "/infix"

  // A prefix that is not a literal stays a placeholder segment.
  val tenant = Router.from { case GET(p"/settings") => Action(Results.Ok("s")) }.withPrefix(prefix)

  // val dead = Router.from { case GET(p"/dead") => ??? }
  val text = "Router.from { case GET(p\"/in-string\") => ??? }"
}
