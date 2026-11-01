package app

import play.api.mvc._
import play.api.routing.sird._
import play.api.routing.Router

class Loader {
  // Comment with fake sird:
  // case GET(p"/fake_comment") =>
  /*
  case POST(p"/fake_block") =>
  */
  val doc = """
    case DELETE(p"/fake_doc") =>
  """

  val router = Router.from {
    case GET(p"/sird/$id") =>
      val brace = "brace } inside"
      val interp = s"sird ${ { val x = "}"; x } }"
      Action { Ok(id) }
    case POST(p"/sird/items") =>
      Action { Ok("item") }
  }
}
