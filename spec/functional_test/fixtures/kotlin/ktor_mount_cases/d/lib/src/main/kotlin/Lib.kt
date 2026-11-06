package lib
import io.ktor.server.routing.*
fun Route.status() {
    get("/status") { call.respondText("s") }
}
fun Route.libRoutes() {
    route("/lib") { status() }
}
