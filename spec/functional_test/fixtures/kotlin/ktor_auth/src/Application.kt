package com.example

import io.ktor.server.application.*
import io.ktor.server.auth.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Application.configureRouting() {
    routing {
        get("/public") {
            call.respondText("public")
        }

        authenticate("auth-jwt") {
            get("/profile") {
                val principal = call.principal<JWTPrincipal>()
                call.respondText("Hello, ${principal}")
            }

            post("/api/data") {
                call.respondText("created")
            }
        }

        get("/health") {
            call.respondText("ok")
        }
    }
}
