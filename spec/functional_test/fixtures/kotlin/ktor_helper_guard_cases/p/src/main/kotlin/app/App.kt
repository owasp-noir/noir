package app
import io.ktor.server.application.*
import io.ktor.server.routing.*
import io.ktor.server.auth.*
import io.ktor.http.*
import codes.DENIED
import other.*

fun ApplicationCall.requireUser() {
    principal<UserIdPrincipal>() ?: throw UnauthorizedException()
}

fun Application.module() {
    routing {
        // Same package, another file.
        get("/gone") {
            if (call.parameters["old"] != null) return@get call.respond(GONE)
            call.requireUser()
            call.respondText("ok")
        }
        // Imported by name.
        get("/denied") {
            if (call.parameters["x"] != null) return@get call.respond(DENIED)
            call.requireUser()
            call.respondText("ok")
        }
        // Wildcard import of a package whose OKAY is a success status.
        get("/okay") {
            if (call.parameters["x"] != null) return@get call.respond(OKAY)
            call.requireUser()
            call.respondText("ok")
        }
        // A local val shadows the package's GONE.
        get("/shadow") {
            val GONE = HttpStatusCode.OK
            if (call.parameters["x"] != null) return@get call.respond(GONE)
            call.requireUser()
            call.respondText("ok")
        }
    }
}
