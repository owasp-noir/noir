package controllers

import play.api.mvc._

class HomeController extends BaseController {
  def index() = Action {
    Ok("Welcome to Play")
  }
}
