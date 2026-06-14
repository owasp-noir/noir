package com.example.ziohttp

import zio._
import zio.http._
import zio.http.codec._
import zio.http.endpoint._

object EndpointDsl {
  // Declarative endpoint DSL. Path params come from the path; the trailing
  // `.out[Int]` must NOT register a phantom `{id2}` path param.
  val getUser =
    Endpoint(Method.GET / "v2" / "users" / int("userId")).out[Int]

  // Query params live on the codec chain, not in a handler block.
  val listPosts =
    Endpoint(Method.GET / "v2" / "users" / int("userId") / "posts")
      .query(HttpCodec.query[String]("name"))
      .out[List[String]]

  // Response headers built with `Headers(Header.X(...))` must not be read as
  // request header params.
  val routes: Routes[Any, Response] = Routes(
    Method.GET / "v2" / "download" -> handler { (req: Request) =>
      Response(
        body = Body.empty,
        headers = Headers(
          Header.ContentType(MediaType.application.`octet-stream`),
          Header.ContentDisposition.attachment("file.bin")
        )
      )
    },
  )
}
