package app
import io.ktor.server.application.*
import io.ktor.server.routing.*
import io.ktor.http.*
import auth.*
val ARCHIVED_YEAR_FORBIDDEN = HttpStatusCode(403, "Forbidden: Archived Year")

fun Application.module() {
    routing {
        post("/soft/{id}") {
            call.requireSoft()
            Repo.delete(call.parameters["id"])
            call.respond(HttpStatusCode.OK)
        }
        post("/soft2") {
            call.requireSoft2()
            Repo.wipe()
        }
        get("/setting") {
            call.requireIfEnabled()
            call.respondText("ok")
        }
        get("/rc") {
            call.requireRc()
            call.respondText("ok")
        }
        get("/shared") {
            call.requireShared()
            call.respondText("ok")
        }
        get("/early") {
            if (call.parameters["preview"] == "1") return@get call.respondText("public preview")
            call.requireUser()
            call.respondText("ok")
        }
        get("/items/{id}") {
            call.requireUser()
            call.respondText("ok")
        }
        get("/real") { call.requireUser(); call.respondText("ok") }
        get("/archived") {
            if (call.parameters["year"] != "2026") return@get call.respond(ARCHIVED_YEAR_FORBIDDEN)
            call.requireUser()
            call.respondText("ok")
        }
        get("/data") {
            if (call.parameters["cached"] != null) return@get call.respond(Cache.data)
            call.requireUser()
            call.respondText("ok")
        }
    }
}
