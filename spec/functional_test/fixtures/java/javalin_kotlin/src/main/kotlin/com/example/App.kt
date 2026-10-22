package com.example

import io.javalin.Javalin
import io.javalin.apibuilder.ApiBuilder.crud
import io.javalin.apibuilder.ApiBuilder.delete
import io.javalin.apibuilder.ApiBuilder.get
import io.javalin.apibuilder.ApiBuilder.path
import io.javalin.http.Context
import io.javalin.http.staticfiles.Location

const val API_PREFIX = "/api"

fun main() {
    val app = Javalin.create { config ->
        config.staticFiles.add { staticFiles ->
            staticFiles.hostedPath = "/assets" // served by the CDN in prod
            staticFiles.directory = "/public"
            staticFiles.location = Location.CLASSPATH
        }
        config.router.apiBuilder {
            path(API_PREFIX) {
                get("/users") { ctx -> ctx.json(listOf<String>()) }
                path("/users/{id}") {
                    get(UserController::getOne)
                    delete { ctx -> ctx.status(204) }
                }
                crud("items/{item-id}", ItemController())
            }
        }
    }.start(7070)

    app.get("/hello") { ctx ->
        val name = ctx.queryParam("name")
        val trace = ctx.header("X-Trace")
        ctx.result("Hello $name ($trace)")
    }
    app.post("/users", UserController::create)
    app.put("/users/{id}") { ctx ->
        val user = ctx.bodyAsClass<User>()
        ctx.header("X-Updated", "true")
        ctx.json(user)
    }
    app.post("/login") { ctx ->
        val username = ctx.formParam("username")
        val password = ctx.formParam("password")
        ctx.cookie("remember", "1")
        ctx.result(AuthService.login(username, password))
    }
    app.delete("/sessions") { ctx ->
        ctx.cookie("session")
    }
    app.ws("/chat/{room}") { ws ->
        ws.onMessage { msg -> msg.send(msg.message()) }
    }

    val defaults = mutableMapOf<String, String>()
    defaults.put("X-Cache", "none")
    val labels = HashMap<String, String>().apply { put("team", "core") }
}

object UserController {
    fun getOne(ctx: Context) {
        ctx.queryParam("expand")
        ctx.json(UserRepository.find(ctx.pathParam("id")))
    }

    fun create(ctx: Context) {
        val user = ctx.bodyAsClass(User::class.java)
        UserRepository.save(user)
    }
}

data class User(val name: String, val email: String)
