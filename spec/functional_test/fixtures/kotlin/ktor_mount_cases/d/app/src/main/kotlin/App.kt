package app
import io.ktor.server.application.*
import io.ktor.server.routing.*
import io.ktor.server.auth.*
import lib.*
fun Application.module() {
    routing {
        libRoutes()
        authenticate("jwt") {
            route("/admin") { status() }
        }
    }
}
