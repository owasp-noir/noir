package com.example.akka

import akka.http.scaladsl.server.Directives._
import akka.http.scaladsl.marshallers.sprayjson.SprayJsonSupport._

case class User(name: String, email: String)
case class Item(id: Int, name: String)

object WebServer {
  val route =
    path("users") {
      concat(
        get {
          val literal = "IgnoredService.nope() { }"
          // CommentedService.nope()
          val users = UserService.list()
          complete(renderUsers(users))
        },
        post {
          entity(as[User]) { user =>
            val created = UserService.create(user)
            AuditLog.write("create", created.name)
            complete(renderUser(created))
          }
        }
      )
    }

  val apiRoute =
    pathPrefix("api") {
      pathPrefix("v1") {
        path("items" / IntNumber) { itemId =>
          concat(
            get {
              val item = ItemService.find(itemId)
              complete(renderItem(item))
            },
            put {
              entity(as[Item]) { item =>
                headerValueByName("Authorization") { token =>
                  val updated = ItemService.update(itemId, item, token)
                  complete(renderItem(updated))
                }
              }
            },
            delete {
              optionalHeaderValueByName("X-API-Key") { apiKey =>
                ItemService.delete(itemId, apiKey)
                complete("deleted")
              }
            }
          )
        }
      }
    }

  val compactRoute = path("compact") { get { complete(HealthService.check()) } }

  val repeatedRoute =
    path("multi") {
      concat(
        get {
          FirstService.call()
          complete("first")
        },
        get {
          SecondService.call()
          complete("second")
        }
      )
    }
}
