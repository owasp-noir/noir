package com.example.tapir.compose

import sttp.tapir._
import sttp.tapir.json.circe._
import sttp.tapir.generic.auto._
import sttp.tapir.server.ServerEndpoint

case class Book(title: String, year: Int)
case class Register_IN(login: String, email: String, password: String)

object ComposeApi {
  // Path constant reused as a prefix.
  private val UserPath = "user"

  // Reusable query-param combinator bound to a val.
  private val limitParameter = query[Option[Int]]("limit").description("max results")

  // Base endpoint carrying a shared '/books' prefix.
  private val baseEndpoint = endpoint.errorOut(stringBody).in("books")

  // Derived endpoint: inherits '/books', multi-line .in whose
  // .description(...) / .example(...) literals must NOT leak into the path.
  val addBook: PublicEndpoint[Book, String, Unit, Any] = baseEndpoint.post
    .in("add")
    .in(
      jsonBody[Book]
        .description("The book to add")
        .example(Book("Pride and Prejudice", 1813))
    )
    .in(header[String]("X-Auth-Token"))

  // Derived endpoint: inherits '/books', resolves the param-const reference.
  val listing = baseEndpoint.get
    .in("list" / "all")
    .in(limitParameter)

  // Const-prefixed routes.
  val register = endpoint.post.in(UserPath / "register").in(jsonBody[Register_IN])
  val getUser  = endpoint.get.in(UserPath)

  // Endpoints inside a List with an Endpoint-typed generic — the type name must
  // not start a chain that swallows the entries.
  val all = List[ServerEndpoint[Any, Any]](
    endpoint.get.in("p1").serverLogic(_ => ???),
    endpoint.get.in("p1" / "p2").serverLogic(_ => ???)
  )
}
