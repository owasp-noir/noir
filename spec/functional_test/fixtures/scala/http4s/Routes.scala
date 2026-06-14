package com.example.http4s

import cats.effect.IO
import org.http4s._
import org.http4s.dsl.io._
import org.http4s.server.Router

case class CreateUser(name: String, email: String)
case class UpdateItem(quantity: Int)

object Matchers {
  object NameQueryParamMatcher extends QueryParamDecoderMatcher[String]("name")
  object SortQueryParamMatcher extends OptionalQueryParamDecoderMatcher[String]("sort")
}

import Matchers._

object Routes {
  val userRoutes: HttpRoutes[IO] = HttpRoutes.of[IO] {
    case GET -> Root / "users" =>
      Ok("list")

    case GET -> Root / "users" / IntVar(id) =>
      Ok(s"user $id")

    case GET -> Root / "posts" / id =>
      Ok(s"post $id")

    case req @ POST -> Root / "users" =>
      req.as[CreateUser].flatMap(u => Ok(u.name))

    case req @ PUT -> Root / "items" / IntVar(id) =>
      req.as[UpdateItem].flatMap(_ => Ok(s"updated $id"))

    case GET -> Root / "search" :? NameQueryParamMatcher(name) +& SortQueryParamMatcher(sort) =>
      Ok(s"search $name")

    case (GET | HEAD) -> Root / "ping" =>
      Ok("pong")

    case req @ POST -> Root / "bulk" => req.as[CreateUser].flatMap { u =>
      Ok(u.name)
    }
  }

  val healthRoutes: HttpRoutes[IO] = HttpRoutes.of[IO] {
    case GET -> Root / "health" =>
      Ok("ok")
  }

  // AuthedRoutes wrapped in a middleware; the user is bound with `as`.
  val secureRoutes: HttpRoutes[IO] = authMiddleware(AuthedRoutes.of[String, IO] {
    case GET -> Root / "profile" as user =>
      Ok(s"profile for $user")

    case req @ POST -> Root / "account" as user =>
      req.as[UpdateItem].flatMap(_ => Ok(s"updated by $user"))
  })

  val httpApp = Router(
    "/api" -> userRoutes,
    "/v1" -> healthRoutes,
    "/auth" -> secureRoutes
  ).orNotFound
}
