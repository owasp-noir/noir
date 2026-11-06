package app
import io.ktor.server.application.*
import io.ktor.server.auth.*
import io.ktor.http.*
// responds 401 but returns normally: the handler keeps running
suspend fun ApplicationCall.requireSoft() {
    val p = principal<UserIdPrincipal>()
    if (p == null) respond(HttpStatusCode.Unauthorized)
}
suspend fun ApplicationCall.requireSoft2() {
    principal<UserIdPrincipal>() ?: return respond(HttpStatusCode.Unauthorized)
}
// setting can open it
fun ApplicationCall.requireIfEnabled() {
    if (!Config.authEnabled) return
    val p = principal<UserIdPrincipal>()
    if (p == null) throw UnauthorizedException()
}
fun RoutingCall.requireRc() {
    val p = principal<UserIdPrincipal>()
    if (p?.name != "admin") throw ForbiddenException()
}
fun ApplicationCall.requireUser() {
    principal<UserIdPrincipal>() ?: throw UnauthorizedException()
}
