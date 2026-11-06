import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Application.betaModule() {
    routing {
        route("/beta") {
            api()

        }
    }
}

fun Route.api() {
    get("ping") {
        call.respondText("beta")
    }
}
