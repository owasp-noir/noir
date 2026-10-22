package com.example.sourcesets

import zio.http._

// Test-only routes: nothing serves them.
object ZioAppSpec {
  val routes = Routes(
    Method.GET / "zio-test-only" -> handler(Response.text("ok"))
  )
}
