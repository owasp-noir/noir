package app
import io.ktor.server.routing.*
class PublicController {
    fun Route.routes() {
        get("/hello") { call.respondText("s") }
    }
}
