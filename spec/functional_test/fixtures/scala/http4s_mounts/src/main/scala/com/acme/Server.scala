package com.acme

import cats.effect.IO
import org.http4s._
import org.http4s.dsl.io._
import org.http4s.server.Router

object Server {
  val health: HttpRoutes[IO] = HttpRoutes.of[IO] {
    case GET -> Root / "ping" => Ok("pong")
  }

  val petRoutes = new PetRoutes("repo")

  // Routes owned by an object (called) and a class instance in another file.
  val httpApp = Router(
    "/users" -> UserEndpoints.endpoints("svc"),
    "/pets" -> petRoutes.routes,
    "/internal" -> health
  ).orNotFound
}
