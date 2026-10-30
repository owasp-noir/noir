package com.example

import play.api._
import play.api.ApplicationLoader.Context
import play.api.mvc._
import play.api.routing.Router
import play.api.routing.sird._

class AppLoader extends ApplicationLoader {
  def load(context: Context): Application = new AppComponents(context).application
}

class AppComponents(context: Context) extends BuiltInComponentsFromContext(context) {
  private def itemsRouter(name: String): Router =
    Router.from {
      case GET(p"/$version") => Action(Results.Ok(version))
      case POST(p"/-/refresh") => Action(Results.Ok("ok"))
    } withPrefix (s"/items/$name")

  private def defaultRouter: Router = Router.from { case GET(p"/health_check") =>
    Action { _ => Results.Ok("ok") }
  }

  lazy val router: Router = List(defaultRouter, itemsRouter("books")).reduce(_ orElse _)
  override lazy val httpFilters = Nil
}
