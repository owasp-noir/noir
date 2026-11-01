package com.example.akka

import akka.http.scaladsl.server.Directives._
import akka.http.scaladsl.server.Route

class WebServer {
  // Comments with fake routes:
  // path("fake_comment") { get { complete("fake") } }
  /*
  path("fake_block") { post { complete("fake") } }
  */
  val doc = """
    path("fake_doc") { delete { complete("fake") } }
  """

  val route: Route =
    pathPrefix("api" / "v1") {
      val prefixStr = s"prefix ${ if (true) "{" else "}" }"
      path("users" / Segment) { id =>
        val brace = "{ brace in string"
        val interp = s"user ${id} with ${ { val x = "}"; x } }"
        get {
          parameter("detail") { detail =>
            complete(s"user $id $detail")
          }
        } ~
        post {
          entity(as[String]) { body =>
            complete("saved")
          }
        }
      } ~
      path("admin") {
        authenticateBasic(realm = "secure", userPassAuthenticator) { user =>
          get {
            complete("admin")
          }
        }
      }
    }
}
