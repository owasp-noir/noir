package controllers

import play.api.mvc._

class HomeController extends AbstractController(null) {
  def index() = Action { request =>
    request.headers.get("X-A")
    Results.Ok("a")
  }
}
