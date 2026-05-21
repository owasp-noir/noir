package com.example.ktor

import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.http.*

fun Route.extensionRoutes() {
    route("/extension") {
        get {
            call.respondText("Extension route")
        }

        route("/method", HttpMethod.Post) {
            handle {
                call.respondText("Method route")
            }
        }
    }
}
