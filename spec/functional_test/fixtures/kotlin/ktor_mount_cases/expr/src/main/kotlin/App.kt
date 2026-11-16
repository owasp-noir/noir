package app
import io.ktor.server.application.*
import io.ktor.server.routing.*
import io.ktor.server.auth.*
fun Application.module() {
    routing {
        route("/api") {
            status()
            authenticate("jwt") {
                orders()
            }
        }
    }
}
