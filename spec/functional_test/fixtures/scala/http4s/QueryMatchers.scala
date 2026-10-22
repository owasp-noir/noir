package example

import org.http4s.dsl.io._

// Declared apart from the routes that use them; the key is the
// constructor argument, whatever the pattern binds it to.
object FindTerm extends QueryParamDecoderMatcher[String]("q")
object FindLimit extends OptionalQueryParamDecoderMatcher[Int]("limit")
