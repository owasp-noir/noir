package app
import io.ktor.server.application.*
import io.ktor.server.routing.*
import io.ktor.server.auth.*
import io.ktor.http.*
val FORBIDDEN = HttpStatusCode.OK
fun ApplicationCall.requireUser() {
    principal<UserIdPrincipal>() ?: throw UnauthorizedException()
}
fun Application.module() {
    routing {
        get("/okconst") {
            if (call.parameters["p"] == "1") return@get call.respond(FORBIDDEN)
            call.requireUser()
            call.respondText("ok")
        }
        get("/collide") {
            val STATUS = HttpStatusCode.OK
            if (call.parameters["p"] == "1") return@get call.respond(STATUS)
            call.requireUser()
            call.respondText("ok")
        }
        get("/fromvalue") {
            if (call.parameters["p"] == "1") return@get call.respond(HttpStatusCode.fromValue(200))
            call.requireUser()
            call.respondText("ok")
        }
        get("/notfound") {
            val id = call.parameters["id"] ?: return@get call.respond(HttpStatusCode.NotFound)
            call.requireUser()
            call.respondText("ok $id")
        }
        get("/var") {
            val status = if (call.parameters["p"] == "1") HttpStatusCode.OK else HttpStatusCode.BadRequest
            if (call.parameters["q"] != null) return@get call.respond(status)
            call.requireUser()
            call.respondText("ok")
        }
        get("/foreach") {
            listOf(1, 2).forEach { if (it == 1) return@forEach }
            call.requireUser()
            call.respondText("ok")
        }
    }
}
