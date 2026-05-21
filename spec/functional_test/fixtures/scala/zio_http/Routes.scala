package com.example.ziohttp

import zio._
import zio.http._

final case class CreateUser(name: String, email: String)
final case class UpdateItem(id: Int, name: String)

object UserApp {

  val routes: Routes[Any, Response] = Routes(
    Method.GET / "hello" -> handler(Response.text("Hello World!")),
    Method.GET / "users" -> handler(Response.text("List of users")),
    Method.GET / "users" / int("userId") -> handler { (userId: Int, req: Request) =>
      Response.text(s"User $userId")
    },
    Method.POST / "users" -> handler { (req: Request) =>
      req.body.to[CreateUser].map(user => Response.text(s"Created ${user.name}"))
    },
    Method.GET / "api" / "v1" / "status" -> handler(Response.text("ok")),
    Method.GET / "api" / "v1" / "items" -> handler { (req: Request) =>
      val category = req.url.queryParam("category")
      val sort = req.url.queryParam("sort")
      Response.text(s"Items in $category sorted $sort")
    },
    Method.GET / "api" / "v1" / "items" / uuid("itemId") -> handler { (itemId: java.util.UUID, req: Request) =>
      Response.text(itemId.toString)
    },
    Method.PUT / "api" / "v1" / "items" / int("itemId") -> handler { (itemId: Int, req: Request) =>
      val auth = req.headers.get("Authorization")
      req.body.to[UpdateItem].map(item => Response.text(s"Updated $itemId"))
    },
    Method.DELETE / "api" / "v1" / "items" / int("itemId") -> handler { (itemId: Int, req: Request) =>
      val apiKey = req.headers.get("X-API-Key")
      Response.text(s"Deleted $itemId")
    },
    Method.POST / "search" -> handler { (req: Request) =>
      val q = req.url.queryParam("q")
      Response.text(s"Search $q")
    },
  )
}
