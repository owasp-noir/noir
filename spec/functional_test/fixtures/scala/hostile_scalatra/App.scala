package com.example.scalatra

import org.scalatra._

class App extends ScalatraServlet {
  // Fake routes in comments:
  // get("/fake_comment") { "fake" }
  /*
  post("/fake_block") { "fake" }
  /* nested: delete("/fake_nested") { "nested" } */
  */
  val doc = """
    get("/fake_doc") { "fake" }
  """

  get("/users/:id") {
    val braceInString = "brace { inside string"
    val interp = s"User ${params("id")} with ${if (true) "{" else "}"}"
    val detail = params("detail")
    val token = request.getHeader("X-Custom-Token")
    Ok(s"user $detail")
  }

  post("/submit") {
    val closing = "closing } inside string"
    val complexInterp = s"hello ${ { val x = "}"; x } }"
    val body = request.body
    Ok("done")
  }
}
