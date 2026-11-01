package com.example.finatra

import com.twitter.finatra.http.Controller

class OrderController extends Controller {
  // Fake routes in comments:
  // get("/fake_comment") { req => "fake" }
  /*
  post("/fake_block") { req => "fake" }
  */
  val doc = """
    delete("/fake_doc") { req => "fake" }
  """

  prefix("/api") {
    val prefixInterp = s"prefix ${ if (true) "{" else "}" }"
    get("/orders/:id") { req =>
      val braceStr = "{ brace in string"
      val interp = s"order ${req.params("id")} with ${ { val x = "}"; x } }"
      val q = req.params("filter")
      response.ok.body("order")
    }

    post("/orders") { req =>
      val closeStr = "close } inside"
      val interp = s"data ${ { val x = "}"; x } }"
      val limit = req.getIntParam("limit")
      response.ok
    }
  }
}
