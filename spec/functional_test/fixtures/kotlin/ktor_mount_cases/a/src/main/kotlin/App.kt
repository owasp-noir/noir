package app
import io.ktor.server.application.*
import io.ktor.server.routing.*
import io.ktor.server.auth.*

fun Application.module() {
    routing {
        authenticate("jwt") {
            route("/a") {
                get("/inline") { call.respondText("x") }
            }
        }
        route("/api") {
            authenticate("jwt") {
                adminRoutes()
            }
            publicRoutes()
        }
        route("/mixed") {
            sharedRoutes()
        }
        authenticate("jwt") {
            route("/mixed") {
                sharedRoutes()
            }
        }
        authenticate("jwt", optional = true) {
            optRoutes()
        }
        route("/cyc") { cycA() }
        authenticate("jwt") { chainOuter() }
    }
}
