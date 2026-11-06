import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Route.libRoutes() {
    get("lib") {
        call.respondText("lib")
    }
}
