package com.example.sourcesets

import akka.http.scaladsl.server.Directives._

// sbt scripted-test project: not part of the shipped application.
object AkkaScripted {
  val route =
    path("akka-scripted-only") {
      get {
        complete("ok")
      }
    }
}
