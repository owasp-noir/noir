package controllers

import play.api.mvc._
import javax.inject._

@Singleton
class HomeController @Inject()(val controllerComponents: ControllerComponents) extends BaseController {
  // Comment with fake action:
  // def fakeAction = Action { Ok("fake") }
  /*
  def blockFake = Action { Ok("block") }
  */
  val doc = """
    def docFake = Action { Ok("doc") }
  """

  def getUser(id: Long) = Action { implicit request: Request[AnyContent] =>
    val braceStr = "brace { inside string"
    val interp = s"User ${id} with ${if (id > 0) "{" else "}"}"
    val headerVal = request.headers.get("X-Auth-Token")
    val queryVal = request.queryString.get("detail")
    Ok(s"user $id")
  }

  def createItem() = Action { implicit request: Request[AnyContent] =>
    val close = "close } inside string"
    val interp = s"data ${ { val k = "}"; k } }"
    val json = request.body.asJson
    Ok("created")
  }
}
