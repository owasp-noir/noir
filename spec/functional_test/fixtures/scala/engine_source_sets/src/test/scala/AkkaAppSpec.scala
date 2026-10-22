package com.example.sourcesets

import akka.http.scaladsl.server.Directives._

// Test-only route table: nothing serves it.
object AkkaAppSpec {
  val route =
    path("akka-test-only") {
      get {
        complete("ok")
      }
    }
}
