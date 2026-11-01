package com.example.ziohttp

import zio._
import zio.http._
import zio.http.codec._

class Routes {
  // Comments with fake routes:
  // Method.DELETE / "fake_comment" -> handler { (req: Request) => Response.ok }
  /*
  Method.PUT / "fake_block" -> handler { (req: Request) => Response.ok }
  */
  val doc = """
    Method.PATCH / "fake_doc" -> handler { (req: Request) => Response.ok }
  """

  val routes = Routes(
    Method.GET / "users" / int("id") -> handler { (id: Int, req: Request) =>
      val brace = "brace { inside"
      val interp = s"user ${id} with ${if (id > 0) "{" else "}"}"
      val filter = req.url.queryParam("filter")
      val token = req.headers.get("X-Token")
      Response.text(s"user $id")
    },

    Method.POST / "items" -> handler { (req: Request) =>
      val close = "close } inside"
      val interp = s"item ${ { val x = "}"; x } }"
      val q = req.url.queryParam("category")
      val body = req.body.asString
      Response.ok
    },

    Endpoint(Method.GET / "declarative" / string("code"))
      .query[String]("q")
      .header[String]("X-Trace")
      .out[String]
  )
}
