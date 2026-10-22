package example

import cats.effect._
import org.http4s._
import org.http4s.dsl.io._

object FindRoutes {
  val findRoutes = HttpRoutes.of[IO] {
    case GET -> Root / "find" :? FindTerm(t) +& FindLimit(n) =>
      Ok(s"$t $n")
  }
}
