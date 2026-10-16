package com.example.sourcesets

import cats.effect.IO
import org.http4s._
import org.http4s.dsl.io._

object Http4sApp {
  val routes = HttpRoutes.of[IO] {
    case GET -> Root / "http4s-live" =>
      Ok("ok")
  }
}
