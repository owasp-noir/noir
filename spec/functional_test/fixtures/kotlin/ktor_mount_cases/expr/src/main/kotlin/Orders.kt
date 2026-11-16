package app
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Route.orders() = route("/orders") {
    get { call.respondText("orders") }
    get("/{orderId}") { call.respondText(call.parameters["orderId"] ?: "") }
    post { call.respondText("created") }
}

fun Route.status() = get("/status") { call.respondText("up") }
