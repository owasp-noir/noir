package com.example.tapir

import sttp.tapir._
import sttp.tapir.json.circe._
import sttp.tapir.generic.auto._
import io.circe.generic.auto._

case class User(id: Int, name: String)
case class Item(id: Int, name: String, price: Double)
case class ApiError(message: String)

object Endpoints {

  val healthEndpoint =
    endpoint
      .get
      .in("health")
      .out(stringBody)

  val getUser =
    endpoint
      .get
      .in("users" / path[Int]("id"))
      .in(query[Option[String]]("include"))
      .out(jsonBody[User])
      .errorOut(jsonBody[ApiError])

  val listUsers = endpoint.get.in("users").out(jsonBody[List[User]])

  val createUser =
    endpoint
      .post
      .in("users")
      .in(jsonBody[User])
      .out(jsonBody[User])

  val updateItem =
    endpoint
      .put
      .in("api" / "v1" / "items" / path[Int]("itemId"))
      .in(header[String]("Authorization"))
      .in(jsonBody[Item])
      .out(jsonBody[Item])

  val deleteItem =
    endpoint
      .delete
      .in("api" / "v1" / "items" / path[Int]("itemId"))
      .in(header[String]("X-API-Key"))

  val searchItems =
    endpoint
      .get
      .in("api" / "v1" / "items")
      .in(query[String]("category"))
      .in(query[Option[String]]("sort"))
      .out(jsonBody[List[Item]])

  val sessionEndpoint =
    endpoint
      .get
      .in("session")
      .in(cookie[String]("sessionId"))
      .out(stringBody)

  // Method-order variant: .in before .get
  val pingEndpoint = endpoint.in("ping").get.out(stringBody)
}
