package com.example.sourcesets

import akka.http.scaladsl.server.Directives._

object AkkaApp {
  val route =
    path("akka-live") {
      get {
        complete("ok")
      }
    }
}
