package app
import io.ktor.server.routing.*

fun Route.users() {
    get("/users") { call.respondText("s") }
}
fun Route.label() {
    get("/labelled") { call.respondText("s") }
}
fun Route.maybe() {
    get("/maybe") { call.respondText("s") }
}
class AdminController {
    fun Route.routes() {
        get("/admin/stats") { call.respondText("s") }
    }
}
