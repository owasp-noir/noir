package demo

import io.ktor.http.*
import io.ktor.resources.*
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.server.sessions.*

data class UserSession(val userId: String)

@Resource("/login")
data class Login(val userId: String = "", val error: String = "")

@Resource("/secret")
class Secret

fun Application.module() {
    routing {
        get<Login> {
            val user = call.sessions.get<UserSession>()
            if (user != null) call.respondRedirect("/") else call.respondText("login form ${it.userId} ${it.error}")
        }
        get<Secret> {
            val user = call.sessions.get<UserSession>() ?: return@get call.respond(HttpStatusCode.Unauthorized)
            call.respondText(user.userId)
        }
    }
}
