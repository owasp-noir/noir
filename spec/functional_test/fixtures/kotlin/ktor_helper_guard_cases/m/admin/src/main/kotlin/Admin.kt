package admin
import io.ktor.server.application.*
import io.ktor.server.auth.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun ApplicationCall.requireAdmin() {
    principal<UserIdPrincipal>() ?: throw UnauthorizedException()
}

fun Application.admin() {
    routing {
        get("/admin/report") {
            call.requireAdmin()
            call.respondText("ok")
        }
    }
}
