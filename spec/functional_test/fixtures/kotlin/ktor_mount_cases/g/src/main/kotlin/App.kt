package app
import io.ktor.server.application.*
import io.ktor.server.routing.*
import io.ktor.server.auth.*
fun Application.module() {
    routing {
        authenticate("jwt", strategy = AuthenticationStrategy.Optional) {
            get("/m") { call.respondText("x") }
        }
    }
}
