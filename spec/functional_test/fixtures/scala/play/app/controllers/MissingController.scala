package controllers

import play.api.mvc._

class MissingController extends BaseController {
  def multipart() = Action { request =>
    request.body.asMultipartFormData
    Ok("multipart")
  }

  def xml() = Action { request =>
    request.body.asXml
    Ok("xml")
  }

  def whitespace() = Action { request =>
    request . body . asJson
    Ok("json")
  }
}
