package com.example

import org.scalatra.test.scalatest._

// Test client calls — `get(...)`/`post(...)` here are HTTP requests, not route
// definitions, and must not be reported as endpoints.
class ApiControllerSpec extends ScalatraFunSuite {
  addServlet(classOf[ApiController], "/api/users/*")

  test("lists users") {
    get("/api/users/42") {
      status should equal(200)
    }
  }

  test("creates a user") {
    post("/api/users/", "name" -> "dave") {
      status should equal(200)
    }
  }
}
