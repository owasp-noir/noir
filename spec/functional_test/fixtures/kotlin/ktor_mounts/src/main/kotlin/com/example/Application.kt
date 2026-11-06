package com.example

import io.ktor.server.application.*
import io.ktor.server.auth.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Application.module() {
    routing {
        get("/healthz") {
            call.respondText("ok")
        }
        sharedRoutes()
        orphanCaller()

        route("/{year}") {
            yearRoutes()
        }
        route("/api") {
            authenticate("admin") {
                adminRoutes()
            }
            publicRoutes()
            authenticate("session", optional = true) {
                optionalRoutes()
            }
        }
        route("/v1") {
            this.sharedRoutes()
        }
        val detached = route("/somewhere") {}
        detached.unplacedRoutes()
    }
}

// Not a Route extension: its routes are not under any mount.
fun orphanCaller() {}

private fun Route.yearRoutes() {
    userRoutes()
    route("/v2") {
        userRoutes()
    }
}
