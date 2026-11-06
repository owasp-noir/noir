package app
import io.ktor.server.application.*
import io.ktor.server.auth.*
import io.ktor.http.*

// refuses only when a feature flag is off; principal read is logging only
fun ApplicationCall.requireFeature(flag: String) {
    if (!Features.enabled(flag)) {
        val who = principal<UserIdPrincipal>()?.name
        log("feature off for $who")
        throw ForbiddenException()
    }
}
// guest-only page, polarity via binding
fun ApplicationCall.guestOnly() {
    val p = principal<UserIdPrincipal>()
    if (p != null) throw ForbiddenException("already signed in")
}
// guest-only via let
fun ApplicationCall.guestOnly2() {
    principal<UserIdPrincipal>()?.let { throw ForbiddenException("signed in") }
}
// rate limit keyed by user, anonymous allowed
suspend fun ApplicationCall.rateLimitUser() {
    val key = principal<UserIdPrincipal>()?.name ?: request.local.remoteHost
    if (Limiter.exceeded(key)) respond(HttpStatusCode.Forbidden)
}
// true guard
fun ApplicationCall.requireUser() {
    principal<UserIdPrincipal>() ?: throw UnauthorizedException()
}
// principal helper
fun ApplicationCall.currentUser(): UserIdPrincipal? = principal<UserIdPrincipal>()
