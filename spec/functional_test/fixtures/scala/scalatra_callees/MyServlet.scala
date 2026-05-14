package com.example.scalatra

import org.scalatra._
import org.json4s.{DefaultFormats, Formats}
import org.scalatra.json._

case class User(name: String, email: String)

class MyServlet extends ScalatraServlet with JacksonJsonSupport {
  protected implicit lazy val jsonFormats: Formats = DefaultFormats

  get("/users/:id") {
    val literal = "IgnoredService.nope()"
    // CommentedService.nope()
    val user = UserService.find(params("id"))
    AuditLog.write("show", user.id)
    json(serializeUser(user))
  }

  post("/users") {
    /*
     * DangerousService.run()
     */
    val payload = UserPayload.from(request.body)
    val user = UserService.create(payload)
    json(serializeUser(user))
  }

  get("/braces") {
    val template = """
    }
    """
    val rendered = BraceService.render()
    json(rendered)
  }

  get("/compact") { json(HealthService.check()) }
}
