package app
import io.ktor.server.routing.*

fun Route.adminRoutes() {
    get("/stats") { call.respondText("s") }
}
fun Route.publicRoutes() {
    get("/hello") { call.respondText("h") }
}
fun Route.sharedRoutes() {
    get("/shared") { call.respondText("h") }
}
fun Route.optRoutes() {
    get("/opt") { call.respondText("h") }
}
fun Route.cycA() {
    get("/ca") { call.respondText("h") }
    route("/b") { cycB() }
}
fun Route.cycB() {
    get("/cb") { call.respondText("h") }
    route("/a") { cycA() }
}
fun Route.chainOuter() {
    route("/outer") { chainInner() }
}
fun Route.chainInner() {
    get("/inner") { call.respondText("h") }
}
