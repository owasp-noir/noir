import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Application.alphaModule() {
    routing {
        route("/alpha") {
            api()
            libRoutes()
        }
    }
}

fun Route.api() {
    get("ping") {
        call.respondText("alpha")
    }
}
