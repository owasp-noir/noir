package auth
import io.ktor.server.application.*
import io.ktor.server.auth.*
fun ApplicationCall.requireShared() {
    principal<UserIdPrincipal>() ?: throw UnauthorizedException()
}
