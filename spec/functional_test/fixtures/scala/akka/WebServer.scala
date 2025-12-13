package com.example.akka

import akka.actor.typed.ActorSystem
import akka.actor.typed.scaladsl.Behaviors
import akka.http.scaladsl.Http
import akka.http.scaladsl.model._
import akka.http.scaladsl.server.Directives._
import akka.http.scaladsl.marshallers.sprayjson.SprayJsonSupport._
import spray.json.DefaultJsonProtocol._

import scala.io.StdIn

case class User(name: String, email: String)
case class Item(id: Int, name: String)

object WebServer {

  implicit val userFormat = jsonFormat2(User)
  implicit val itemFormat = jsonFormat2(Item)

  def main(args: Array[String]): Unit = {

    implicit val system = ActorSystem(Behaviors.empty, "my-system")
    implicit val executionContext = system.executionContext

    val route =
      concat(
        path("hello") {
          get {
            complete(HttpEntity(ContentTypes.`text/html(UTF-8)`, "<h1>Hello World!</h1>"))
          }
        },
        path("users" / IntNumber) { userId =>
          get {
            parameter("filter") { filter =>
              complete(s"User $userId with filter $filter")
            }
          }
        },
        path("users") {
          concat(
            get {
              complete("List of users")
            },
            post {
              entity(as[User]) { user =>
                complete(s"Created user: ${user.name}")
              }
            }
          )
        },
        pathPrefix("api") {
          concat(
            path("status") {
              get {
                complete("API is running")
              }
            },
            pathPrefix("v1") {
              concat(
                path("items") {
                  get {
                    parameters("category", "sort".optional) { (category, sort) =>
                      complete(s"Items in category $category, sort: $sort")
                    }
                  }
                },
                path("items" / IntNumber) { itemId =>
                  concat(
                    get {
                      complete(s"Item $itemId")
                    },
                    put {
                      entity(as[Item]) { item =>
                        headerValueByName("Authorization") { token =>
                          complete(s"Updated item $itemId with token")
                        }
                      }
                    },
                    delete {
                      optionalHeaderValueByName("X-API-Key") { apiKey =>
                        complete(s"Deleted item $itemId")
                      }
                    }
                  )
                }
              )
            }
          )
        },
        path("search") {
          post {
            parameter("q") { query =>
              complete(s"Search results for: $query")
            }
          }
        }
      )

    val bindingFuture = Http().newServerAt("localhost", 8080).bind(route)

    println(s"Server now online. Please navigate to http://localhost:8080/hello\nPress RETURN to stop...")
    StdIn.readLine()
    bindingFuture
      .flatMap(_.unbind())
      .onComplete(_ => system.terminate())
  }
}
