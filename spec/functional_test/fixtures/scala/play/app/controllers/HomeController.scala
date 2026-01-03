package controllers

import play.api.mvc._
import play.api.libs.json._

class HomeController extends BaseController {
  def index() = Action {
    Ok("Welcome to Play")
  }
}

class Users extends BaseController {
  def list() = Action {
    Ok("User list")
  }

  def show(id: Long) = Action {
    Ok(s"User $id")
  }

  def create() = Action {
    Ok("User created")
  }

  def update(id: Long) = Action {
    Ok(s"User $id updated")
  }

  def delete(id: Long) = Action {
    Ok(s"User $id deleted")
  }
}

class Search extends BaseController {
  def search(q: String, filter: String) = Action {
    Ok(s"Search results for $q with filter $filter")
  }
}

class Posts extends BaseController {
  def show(userId: Long, postId: Long) = Action {
    Ok(s"Post $postId from user $userId")
  }
}

class Items extends BaseController {
  def list(category: Option[String], page: Int) = Action {
    Ok(s"Items in category ${category.getOrElse("all")}, page $page")
  }
}

class Files extends BaseController {
  def download(path: String) = Action {
    Ok(s"Downloading file from $path")
  }
}

class Upload extends BaseController {
  def file() = Action {
    Ok("File uploaded")
  }
}

class Api extends BaseController {
  def protectedEndpoint() = Action { request =>
    val authToken = request.headers.get("Authorization").getOrElse("none")
    val sessionId = request.cookies.get("session_id").map(_.value).getOrElse("none")
    Ok(s"Protected endpoint - Auth: $authToken, Session: $sessionId")
  }

  def postData() = Action { request =>
    val contentType = request.headers.get("Content-Type").getOrElse("unknown")
    val json = request.body.asJson
    Ok(Json.toJson(json))
  }
}

class Assets extends BaseController {
  def at(path: String, file: String) = Action {
    Ok(s"Asset $path/$file")
  }
}
