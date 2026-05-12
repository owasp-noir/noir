package com.example.ktor

import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Application.configureRouting() {
    routing {
        post("/users") {
            val name = call.parameters["name"]
            val saved = service.save(name)
            AuditLog.write(saved)
            call.respondText(saved)
        }

        get("/profile") {
            val built = this.buildProfile()
            AuditLog.write(built)
            call.respondText(built)
        }

        get("/legacy") {
            AuditLog.write("legacy")
            call.respondText(getLegacy().toString())
        }

        route("/admin") {
            get("/dashboard") {
                renderDashboard()
            }
        }
    }
}
