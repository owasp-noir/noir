package controllers

import play.api.mvc._

class HealthController extends BaseController {
  def check() = Action {
    Ok("ok")
  }
}
