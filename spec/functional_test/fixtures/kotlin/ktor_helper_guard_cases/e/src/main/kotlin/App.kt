package app
import io.ktor.server.application.*
import io.ktor.server.routing.*
import io.ktor.http.*

fun Application.module() {
    routing {
        get("/feature") {
            call.requireFeature("beta")
            call.respondText("ok")
        }
        get("/guest") {
            call.guestOnly()
            call.respondText("ok")
        }
        get("/guest2") {
            call.guestOnly2()
            call.respondText("ok")
        }
        get("/rl") {
            call.rateLimitUser()
            call.respondText("ok")
        }
        get("/branch") {
            if (call.parameters["draft"] != null) call.requireUser()
            call.respondText("ok")
        }
        get("/str") {
            call.respondText("call requireUser() to sign in")
        }
        get("/unrelated") {
            val u = call.currentUser(); val q = call.parameters.get("q") ?: throw ForbiddenException()
            call.respondText("ok $u $q")
        }
        get("/real") {
            call.requireUser()
            call.respondText("ok")
        }
    }
}
