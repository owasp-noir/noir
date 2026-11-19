package com.acme

import cats.effect.IO
import org.http4s._
import org.http4s.dsl.io._

object UserEndpoints {
  def endpoints(service: String): HttpRoutes[IO] = HttpRoutes.of[IO] {
    case GET -> Root => Ok("list")
    case GET -> Root / LongVar(id) => Ok("one")
  }
}

class PetRoutes(repo: String) {
  val routes: HttpRoutes[IO] = HttpRoutes.of[IO] {
    case req @ POST -> Root => Ok("created")
    case DELETE -> Root / name => Ok("deleted")
  }
}
