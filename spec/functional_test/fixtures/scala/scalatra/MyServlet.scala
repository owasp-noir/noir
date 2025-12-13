package com.example.scalatra

import org.scalatra._
import org.json4s.{DefaultFormats, Formats}
import org.scalatra.json._

case class User(name: String, email: String)
case class Item(id: Int, name: String, category: String)

class MyServlet extends ScalatraServlet with JacksonJsonSupport {

  protected implicit lazy val jsonFormats: Formats = DefaultFormats

  before() {
    contentType = formats("json")
  }

  get("/") {
    <html><body>Welcome to Scalatra</body></html>
  }

  get("/hello") {
    "Hello World!"
  }

  get("/users/:id") {
    val userId = params("id")
    s"User $userId"
  }

  get("/users/:id/posts/:postId") {
    val userId = params("id")
    val postId = params("postId")
    s"User $userId, Post $postId"
  }

  get("/search") {
    val query = params("q")
    val filter = params("filter")
    s"Search: $query, Filter: $filter"
  }

  post("/users") {
    val user = parsedBody.extract[User]
    s"Created user: ${user.name}"
  }

  put("/users/:id") {
    val userId = params("id")
    val user = parsedBody.extract[User]
    val authHeader = request.getHeader("Authorization")
    s"Updated user $userId with token $authHeader"
  }

  delete("/users/:id") {
    val userId = params("id")
    val apiKey = request.getHeader("X-API-Key")
    s"Deleted user $userId"
  }

  get("/items") {
    val tags = multiParams("tags")
    s"Items with tags: ${tags.mkString(", ")}"
  }

  post("/upload") {
    val body = request.body
    "File uploaded"
  }

  get("/profile") {
    val sessionId = cookies.get("session")
    s"Profile for session: $sessionId"
  }

  get("/download/*") {
    val path = multiParams("splat").head
    s"Download: $path"
  }
}
