package shop
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

// Same name, another module, no check at all.
fun ApplicationCall.requireAdmin() {
    application.log.info("admin page viewed")
}

fun Application.shop() {
    routing {
        get("/shop/report") {
            call.requireAdmin()
            call.respondText("ok")
        }
    }
}
