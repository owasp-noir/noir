package admin
import io.ktor.server.application.*
import io.ktor.server.auth.*
fun ApplicationCall.validate() {
    if (principal<UserIdPrincipal>() == null) throw UnauthorizedException()
}
