package com.example.pekko

import org.apache.pekko.actor.typed.ActorSystem
import org.apache.pekko.actor.typed.scaladsl.Behaviors
import org.apache.pekko.http.scaladsl.Http
import org.apache.pekko.http.scaladsl.server.Directives._

object WebServer {
  def main(args: Array[String]): Unit = {
    implicit val system = ActorSystem(Behaviors.empty, "pekko-system")

    val route =
      concat(
        path("hello") {
          get {
            complete("Hello from Pekko")
          }
        },
        pathPrefix("api") {
          path("items" / IntNumber) { itemId =>
            concat(
              get {
                parameter("sort") { sort =>
                  complete(s"Item $itemId sorted by $sort")
                }
              },
              delete {
                headerValueByName("X-API-Key") { key =>
                  complete(s"Deleted $itemId")
                }
              }
            )
          }
        }
      )

    Http().newServerAt("localhost", 8080).bind(route)
  }
}
