package com.example.http4s

import org.http4s._
import org.http4s.dsl.io._
import cats.effect.IO

object QueryMatchers {
  object PageMatcher extends QueryParamDecoderMatcher[Int]("page")
}

class Routes {
  import QueryMatchers._

  // Commented out fake route:
  // case GET -> Root / "fake_comment" => Ok("fake")
  /*
  case DELETE -> Root / "fake_block" => Ok("fake block")
  /* nested comment: case POST -> Root / "fake_nested" => Ok() */
  */

  val docString = """
    Here is an example route:
    case PUT -> Root / "fake_doc" => Ok("fake doc")
  """

  val routes = HttpRoutes.of[IO] {
    case GET -> Root / "users" / IntVar(id) =>
      val braceStr = "curly { inside string"
      val interp = s"User ${id} with ${if (id > 0) "{" else "}"}"
      val charBrace = '}'
      Ok(s"user $id")

    case req @ POST -> Root / "users" =>
      val parenStr = "paren ( inside string"
      val closeBraceStr = "closing } inside string"
      req.as[UserDto].flatMap { dto =>
        Ok("created")
      }

    case GET -> Root / "items" :? PageMatcher(page) =>
      Ok(s"page $page")
  }
}

case class UserDto(name: String)
