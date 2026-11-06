import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Application.api() {
    routing {
        get("/healthz") {
            call.respond(HttpStatusCode.OK)
        }
        get("/votes") {
            val votes = listOf(1, 2, 3)
            call.respond(votes)
        }
        get("/qualified") {
            call.respond(io.ktor.server.thymeleaf.ThymeleafContent("page", emptyMap()))
        }
    }
}
