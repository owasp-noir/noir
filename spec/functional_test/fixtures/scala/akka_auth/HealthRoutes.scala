package com.example

import akka.http.scaladsl.server.Directives._

object HealthRoutes {
  // No auth directives anywhere in this file
  val healthRoute =
    pathPrefix("public") {
      path("health") {
        get {
          complete("ok")
        }
      }
    }
}
