package com.example

import org.scalatra._

// Mounted at "/api/users" in ScalatraBootstrap, so every route below is served
// under that prefix.
class ApiController extends ScalatraServlet {
  get("/") {
    "list of users"
  }

  get("/:id") {
    val id = params("id")
    s"user $id"
  }

  post("/") {
    val name = params("name")
    s"created $name"
  }
}
