package app
import io.ktor.server.routing.*
fun Route.crud() {
    get { call.respondText("s") }
}
fun Route.secret() {
    get("/secret") { call.respondText("s") }
}
