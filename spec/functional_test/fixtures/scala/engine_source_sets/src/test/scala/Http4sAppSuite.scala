package com.example.sourcesets

import cats.effect.IO
import org.http4s._
import org.http4s.dsl.io._

// Test-only route table: nothing serves it.
object Http4sAppSuite {
  val routes = HttpRoutes.of[IO] {
    case GET -> Root / "http4s-test-only" =>
      Ok("ok")
  }
}
